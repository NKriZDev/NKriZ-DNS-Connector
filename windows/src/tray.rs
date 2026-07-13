use crate::config::APP_TITLE;
use crate::ddns;
use crate::dns::{apply_automatic_dns, apply_custom_dns, refresh_status, DnsMode};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::HBRUSH;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NOTIFYICONDATAW,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreatePopupMenu, CreateWindowExW, DefWindowProcW, DestroyMenu, DestroyWindow,
    DispatchMessageW, GetMessageW, InsertMenuW, LoadIconW, PostMessageW, PostQuitMessage,
    RegisterClassW, SetForegroundWindow, TrackPopupMenu, TranslateMessage, HMENU, MENU_ITEM_FLAGS,
    MF_BYCOMMAND, MF_CHECKED, MF_DISABLED, MF_ENABLED, MF_GRAYED, MF_SEPARATOR, MF_STRING,
    MF_UNCHECKED, MSG, TPM_BOTTOMALIGN, TPM_LEFTALIGN, TPM_RIGHTBUTTON,
    WINDOW_STYLE, WM_APP, WM_COMMAND, WM_DESTROY, WM_LBUTTONUP, WM_RBUTTONUP, WM_USER,
    WNDCLASSW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_OVERLAPPED, IDI_APPLICATION,
};

const WM_TRAYICON: u32 = WM_USER + 42;
const ID_TRAYICON: u32 = 1;

const ID_STATUS: u32 = 1001;
const ID_AUTOMATIC: u32 = 1002;
const ID_CUSTOM: u32 = 1003;
const ID_REFRESH_STATUS: u32 = 1004;
const ID_REFRESH_IP: u32 = 1005;
const ID_IP_OUTPUT: u32 = 1006;
const ID_QUIT: u32 = 1007;

const WM_WORKER_DONE: u32 = WM_APP + 1;

#[derive(Debug)]
enum WorkerRequest {
    ApplyCustom,
    ApplyAutomatic,
    RefreshStatus,
    RefreshIp,
}

#[derive(Debug)]
enum WorkerResponse {
    StatusUpdated {
        message: String,
        mode: DnsMode,
    },
    ActionMessage {
        message: String,
        success: bool,
    },
    IpRefreshed {
        output: String,
    },
}

struct AppState {
    hwnd: HWND,
    worker_tx: Sender<WorkerRequest>,
    status_text: String,
    ip_text: String,
    mode: DnsMode,
    busy: bool,
}

static mut APP_STATE: Option<AppState> = None;

pub fn run() {
    unsafe {
        let instance = GetModuleHandleW(None).expect("module handle");
        let class_name = to_wide("NKriZDNSConnectorWindow");

        let window_class = WNDCLASSW {
            lpfnWndProc: Some(window_proc),
            hInstance: HINSTANCE(instance.0),
            lpszClassName: PCWSTR(class_name.as_ptr()),
            hIcon: LoadIconW(None, IDI_APPLICATION).unwrap_or_default(),
            hbrBackground: HBRUSH::default(),
            ..Default::default()
        };

        RegisterClassW(&window_class);

        let hwnd = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
            PCWSTR(class_name.as_ptr()),
            PCWSTR(to_wide(APP_TITLE).as_ptr()),
            WINDOW_STYLE(WS_OVERLAPPED.0),
            0,
            0,
            0,
            0,
            None,
            None,
            Some(HINSTANCE(instance.0)),
            None,
        )
        .expect("create window");

        let (worker_tx, worker_rx) = mpsc::channel();
        spawn_worker(worker_rx, hwnd);

        APP_STATE = Some(AppState {
            hwnd,
            worker_tx,
            status_text: "Checking DNS...".to_string(),
            ip_text: "IP: (not refreshed yet)".to_string(),
            mode: DnsMode::Unknown,
            busy: false,
        });

        add_tray_icon(hwnd);
        queue_worker(WorkerRequest::RefreshStatus);

        let mut message = MSG::default();
        while GetMessageW(&mut message, None, 0, 0).into() {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

fn spawn_worker(worker_rx: Receiver<WorkerRequest>, hwnd: HWND) {
    let raw_hwnd = hwnd.0 as isize;
    thread::spawn(move || {
        while let Ok(request) = worker_rx.recv() {
            let response = match request {
                WorkerRequest::ApplyCustom => {
                    let result = apply_custom_dns();
                    let action = match result {
                        Ok(message) => WorkerResponse::ActionMessage {
                            message,
                            success: true,
                        },
                        Err(error) => WorkerResponse::ActionMessage {
                            message: error,
                            success: false,
                        },
                    };
                    post_worker_response(raw_hwnd, action);
                    let status = refresh_status();
                    WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    }
                }
                WorkerRequest::ApplyAutomatic => {
                    let result = apply_automatic_dns();
                    let action = match result {
                        Ok(message) => WorkerResponse::ActionMessage {
                            message,
                            success: true,
                        },
                        Err(error) => WorkerResponse::ActionMessage {
                            message: error,
                            success: false,
                        },
                    };
                    post_worker_response(raw_hwnd, action);
                    let status = refresh_status();
                    WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    }
                }
                WorkerRequest::RefreshStatus => {
                    let status = refresh_status();
                    WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    }
                }
                WorkerRequest::RefreshIp => match ddns::refresh_ip() {
                    Ok(output) => WorkerResponse::IpRefreshed { output },
                    Err(error) => WorkerResponse::IpRefreshed {
                        output: format!("Error: {error}"),
                    },
                },
            };

            post_worker_response(raw_hwnd, response);
        }
    });
}

fn post_worker_response(raw_hwnd: isize, response: WorkerResponse) {
    unsafe {
        let hwnd = HWND(raw_hwnd as *mut _);
        let boxed = Box::new(response);
        let ptr = Box::into_raw(boxed) as isize;
        let _ = PostMessageW(Some(hwnd), WM_WORKER_DONE, WPARAM(ptr as usize), LPARAM(0));
    }
}

fn queue_worker(request: WorkerRequest) {
    unsafe {
        if let Some(state) = APP_STATE.as_mut() {
            if state.busy {
                return;
            }
            state.busy = true;
            let _ = state.worker_tx.send(request);
        }
    }
}

unsafe extern "system" fn window_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_WORKER_DONE => {
            let ptr = wparam.0 as *mut WorkerResponse;
            if !ptr.is_null() {
                let response = Box::from_raw(ptr);
                apply_worker_response(*response);
            }
            LRESULT(0)
        }
        WM_TRAYICON => {
            if lparam.0 as u32 == WM_LBUTTONUP || lparam.0 as u32 == WM_RBUTTONUP {
                show_menu(hwnd);
            }
            LRESULT(0)
        }
        WM_COMMAND => {
            let command_id = (wparam.0 & 0xFFFF) as u32;
            handle_command(command_id);
            LRESULT(0)
        }
        WM_DESTROY => {
            remove_tray_icon(hwnd);
            PostQuitMessage(0);
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn handle_command(command_id: u32) {
    match command_id {
        ID_AUTOMATIC => queue_worker(WorkerRequest::ApplyAutomatic),
        ID_CUSTOM => queue_worker(WorkerRequest::ApplyCustom),
        ID_REFRESH_STATUS => queue_worker(WorkerRequest::RefreshStatus),
        ID_REFRESH_IP => {
            unsafe {
                if let Some(state) = APP_STATE.as_mut() {
                    state.ip_text = "IP: Refreshing...".to_string();
                }
            }
            queue_worker(WorkerRequest::RefreshIp);
        }
        ID_QUIT => unsafe {
            if let Some(state) = APP_STATE.as_ref() {
                let _ = DestroyWindow(state.hwnd);
            }
        },
        _ => {}
    }
}

fn apply_worker_response(response: WorkerResponse) {
    unsafe {
        let Some(state) = APP_STATE.as_mut() else {
            return;
        };

        match response {
            WorkerResponse::StatusUpdated { message, mode } => {
                state.status_text = message;
                state.mode = mode;
                state.busy = false;
            }
            WorkerResponse::ActionMessage { message, success } => {
                state.status_text = if success {
                    message
                } else {
                    format!("Failed: {message}")
                };
                state.busy = false;
            }
            WorkerResponse::IpRefreshed { output } => {
                state.ip_text = format!("IP: {output}");
                state.busy = false;
            }
        }
    }
}

unsafe fn add_tray_icon(hwnd: HWND) {
    let mut data = NOTIFYICONDATAW {
        cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: ID_TRAYICON,
        uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        uCallbackMessage: WM_TRAYICON,
        hIcon: LoadIconW(None, IDI_APPLICATION).unwrap_or_default(),
        szTip: wide_tip(APP_TITLE),
        ..Default::default()
    };

    let _ = Shell_NotifyIconW(NIM_ADD, &mut data);
}

unsafe fn remove_tray_icon(hwnd: HWND) {
    let mut data = NOTIFYICONDATAW {
        cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: ID_TRAYICON,
        ..Default::default()
    };
    let _ = Shell_NotifyIconW(NIM_DELETE, &mut data);
}

unsafe fn show_menu(hwnd: HWND) {
    let Some(state) = APP_STATE.as_ref() else {
        return;
    };

    let menu = CreatePopupMenu().expect("popup menu");
    let enabled = if state.busy {
        MF_GRAYED | MF_DISABLED
    } else {
        MF_ENABLED
    };

    append_text_item(menu, ID_STATUS, &state.status_text, MF_DISABLED | MF_STRING);
    append_separator(menu);
    append_check_item(
        menu,
        ID_AUTOMATIC,
        "Automatic (DHCP)",
        state.mode == DnsMode::Automatic,
        enabled,
    );
    append_check_item(
        menu,
        ID_CUSTOM,
        "NKriZ DNS",
        state.mode == DnsMode::Custom,
        enabled,
    );
    append_separator(menu);
    append_text_item(menu, ID_REFRESH_STATUS, "Refresh Status", enabled | MF_STRING);
    append_text_item(menu, ID_REFRESH_IP, "Refresh IP", enabled | MF_STRING);
    append_text_item(menu, ID_IP_OUTPUT, &state.ip_text, MF_DISABLED | MF_STRING);
    append_separator(menu);
    append_text_item(menu, ID_QUIT, "Quit", MF_STRING);

    let _ = SetForegroundWindow(hwnd);
    let _ = TrackPopupMenu(
        menu,
        TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON,
        0,
        0,
        None,
        hwnd,
        None,
    );
    let _ = DestroyMenu(menu);
}

unsafe fn append_text_item(menu: HMENU, id: u32, text: &str, flags: MENU_ITEM_FLAGS) {
    let wide = to_wide(text);
    let _ = InsertMenuW(
        menu,
        id,
        flags | MF_BYCOMMAND,
        id as usize,
        PCWSTR(wide.as_ptr()),
    );
}

unsafe fn append_separator(menu: HMENU) {
    let _ = InsertMenuW(
        menu,
        u32::MAX,
        MF_SEPARATOR | MF_BYCOMMAND,
        0,
        PCWSTR::null(),
    );
}

unsafe fn append_check_item(
    menu: HMENU,
    id: u32,
    text: &str,
    checked: bool,
    enabled: MENU_ITEM_FLAGS,
) {
    append_text_item(
        menu,
        id,
        text,
        enabled
            | if checked { MF_CHECKED } else { MF_UNCHECKED }
            | MF_STRING,
    );
}

fn to_wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn wide_tip(value: &str) -> [u16; 128] {
    let mut buffer = [0u16; 128];
    let wide = to_wide(value);
    let len = wide.len().min(buffer.len());
    buffer[..len].copy_from_slice(&wide[..len]);
    buffer
}
