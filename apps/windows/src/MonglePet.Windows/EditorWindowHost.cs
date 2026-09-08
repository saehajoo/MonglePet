using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using MonglePet.Shell;
using Windows.Graphics;
using Windows.System;

namespace MonglePet.Windows;

/// <summary>
/// Hosts a staged editor in its own owned WinUI window. ContentDialog cannot
/// safely open another ContentDialog on the same XamlRoot, while the pet image
/// workflow needs an animation editor followed by PNG or sprite editors.
/// </summary>
internal sealed class EditorWindowHost : Window
{
    private const int OwnerWindowIndex = -8;
    private const uint NoActivate = 0x0010;
    private const uint NoSize = 0x0001;
    private const uint NoZOrder = 0x0004;
    private readonly TaskCompletionSource<bool> _completion = new(
        TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Func<string?>? _validation;
    private readonly Func<Task>? _acceptAction;
    private readonly EditorDraftState? _draftState;
    private readonly InfoBar _validationInfoBar;
    private nint _ownerWindow;
    private bool _accepted;
    private bool _isAccepting;
    private bool _allowClose;
    private bool _discardConfirmationIsOpen;
    private bool _isClosed;

    public EditorWindowHost(
        string title,
        string description,
        FrameworkElement editor,
        string primaryButtonText,
        string footerText,
        int width,
        int height,
        Func<string?>? validation = null,
        Func<string>? draftFingerprint = null,
        Func<Task>? acceptAction = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentNullException.ThrowIfNull(editor);

        Title = title;
        _validation = validation;
        _acceptAction = acceptAction;
        _draftState = draftFingerprint is null ? null : new EditorDraftState(draftFingerprint);
        SystemBackdrop = new MicaBackdrop();

        _validationInfoBar = new InfoBar
        {
            IsOpen = false,
            Severity = InfoBarSeverity.Error,
            Title = "확인해 주세요",
            Margin = new Thickness(20, 0, 20, 12),
        };

        var titleText = new TextBlock
        {
            Text = title,
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        };
        var descriptionText = new TextBlock
        {
            Text = description,
            TextWrapping = TextWrapping.Wrap,
            Foreground = new SolidColorBrush(Colors.Gray),
            Margin = new Thickness(0, 4, 0, 0),
        };
        var header = new StackPanel
        {
            Padding = new Thickness(20, 16, 20, 14),
        };
        header.Children.Add(titleText);
        header.Children.Add(descriptionText);

        var cancelButton = new Button
        {
            Content = "취소",
            MinWidth = 88,
        };
        cancelButton.Click += (_, _) => RequestClose();

        var primaryButton = new Button
        {
            Content = primaryButtonText,
            MinWidth = 112,
            Style = Application.Current.Resources["AccentButtonStyle"] as Style,
        };
        primaryButton.Click += async (_, _) => await AcceptAsync();

        var footerButtons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        footerButtons.Children.Add(cancelButton);
        footerButtons.Children.Add(primaryButton);

        var footer = new Grid
        {
            Padding = new Thickness(20, 12, 20, 12),
            ColumnSpacing = 16,
        };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(new TextBlock
        {
            Text = footerText,
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(Colors.Gray),
            FontSize = 12,
        });
        Grid.SetColumn(footerButtons, 1);
        footer.Children.Add(footerButtons);

        var editorBorder = new Border
        {
            Child = editor,
            Padding = new Thickness(20),
        };

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(header);
        Grid.SetRow(editorBorder, 1);
        root.Children.Add(editorBorder);
        Grid.SetRow(_validationInfoBar, 2);
        root.Children.Add(_validationInfoBar);
        Grid.SetRow(footer, 3);
        root.Children.Add(footer);

        var enterAccelerator = new KeyboardAccelerator { Key = VirtualKey.Enter };
        enterAccelerator.Invoked += async (_, args) =>
        {
            await AcceptAsync();
            args.Handled = true;
        };
        root.KeyboardAccelerators.Add(enterAccelerator);
        var escapeAccelerator = new KeyboardAccelerator { Key = VirtualKey.Escape };
        escapeAccelerator.Invoked += (_, args) =>
        {
            RequestClose();
            args.Handled = true;
        };
        root.KeyboardAccelerators.Add(escapeAccelerator);

        Content = root;
        AppWindow.Resize(new SizeInt32(width, height));
        AppWindow.Closing += AppWindow_Closing;
        Closed += EditorWindowHost_Closed;
    }

    public nint WindowHandle => WinRT.Interop.WindowNative.GetWindowHandle(this);

    public Task<bool> ShowAsync(nint ownerWindow)
    {
        _ownerWindow = ownerWindow;
        nint window = WindowHandle;
        if (_ownerWindow != nint.Zero)
        {
            _ = SetWindowLongPtr(window, OwnerWindowIndex, _ownerWindow);
            _ = EnableWindow(_ownerWindow, false);
        }
        CenterOverOwner(window, _ownerWindow);
        Activate();
        return _completion.Task;
    }

    public void ShowValidationError(string message)
    {
        _validationInfoBar.Message = message;
        _validationInfoBar.IsOpen = true;
    }

    private async Task AcceptAsync()
    {
        if (_isAccepting)
        {
            return;
        }
        string? error = _validation?.Invoke();
        if (!string.IsNullOrWhiteSpace(error))
        {
            ShowValidationError(error);
            return;
        }
        _validationInfoBar.IsOpen = false;
        _isAccepting = true;
        try
        {
            if (_acceptAction is not null)
            {
                await _acceptAction();
            }
        }
        catch (Exception exception)
        {
            ShowValidationError(exception.Message);
            return;
        }
        finally
        {
            _isAccepting = false;
        }
        _accepted = true;
        _allowClose = true;
        Close();
    }

    private void RequestClose()
    {
        if (_isAccepting)
        {
            return;
        }
        if (_allowClose || _accepted || !HasUnsavedChanges())
        {
            _allowClose = true;
            Close();
            return;
        }
        _ = ConfirmDiscardAsync();
    }

    private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_isAccepting)
        {
            args.Cancel = true;
            return;
        }
        if (_allowClose || _accepted || !HasUnsavedChanges())
        {
            return;
        }
        args.Cancel = true;
        _ = ConfirmDiscardAsync();
    }

    private bool HasUnsavedChanges() => _draftState?.HasChanges == true;

    private async Task ConfirmDiscardAsync()
    {
        if (_discardConfirmationIsOpen || _allowClose || _accepted)
        {
            return;
        }
        _discardConfirmationIsOpen = true;
        try
        {
            var dialog = new ContentDialog
            {
                XamlRoot = (Content as FrameworkElement)?.XamlRoot,
                Title = "변경사항을 버릴까요?",
                Content = "아직 저장하지 않은 변경사항은 사라집니다. 저장 도중 일부만 적용된 경우 이미 저장된 내용은 유지됩니다.",
                PrimaryButtonText = "계속 편집",
                SecondaryButtonText = "변경사항 버리기",
                DefaultButton = ContentDialogButton.Primary,
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Secondary)
            {
                _allowClose = true;
                Close();
            }
        }
        finally
        {
            _discardConfirmationIsOpen = false;
        }
    }

    private void EditorWindowHost_Closed(object sender, WindowEventArgs args)
    {
        if (_isClosed)
        {
            return;
        }
        _isClosed = true;
        AppWindow.Closing -= AppWindow_Closing;
        if (_ownerWindow != nint.Zero)
        {
            _ = EnableWindow(_ownerWindow, true);
            _ = SetForegroundWindow(_ownerWindow);
        }
        _completion.TrySetResult(_accepted);
    }

    private static void CenterOverOwner(nint window, nint owner)
    {
        if (owner == nint.Zero ||
            !GetWindowRect(owner, out NativeRect ownerRect) ||
            !GetWindowRect(window, out NativeRect windowRect))
        {
            return;
        }
        int width = windowRect.Right - windowRect.Left;
        int height = windowRect.Bottom - windowRect.Top;
        int x = ownerRect.Left + ((ownerRect.Right - ownerRect.Left - width) / 2);
        int y = ownerRect.Top + ((ownerRect.Bottom - ownerRect.Top - height) / 2);
        _ = SetWindowPos(window, nint.Zero, x, y, 0, 0, NoSize | NoZOrder | NoActivate);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint window, int index, nint value);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnableWindow(nint window, [MarshalAs(UnmanagedType.Bool)] bool enabled);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint window, out NativeRect rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint window,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
