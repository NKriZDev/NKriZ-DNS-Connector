use crate::config::APP_TITLE;
use crate::ddns;
use crate::dns::{apply_automatic_dns, apply_custom_dns, refresh_status, DnsMode};
use muda::{CheckMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use tray_icon::{TrayIcon, TrayIconBuilder, TrayIconEvent};

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

struct UiHandles {
    status_item: MenuItem,
    automatic_item: CheckMenuItem,
    custom_item: CheckMenuItem,
    refresh_status_item: MenuItem,
    refresh_ip_item: MenuItem,
    ip_output_item: MenuItem,
    quit_item: MenuItem,
}

struct AppState {
    worker_tx: Sender<WorkerRequest>,
    handles: UiHandles,
    busy: bool,
}

pub fn run() {
    init_gtk();

    let (worker_tx, worker_rx) = mpsc::channel::<WorkerRequest>();
    let (response_tx, response_rx) = mpsc::channel::<WorkerResponse>();
    spawn_worker(worker_rx, response_tx);

    let menu = Menu::new();
    let status_item = MenuItem::new("Checking DNS...", true, None);
    let automatic_item = CheckMenuItem::new("Automatic (DHCP)", true, false, None);
    let custom_item = CheckMenuItem::new("NKriZ DNS", true, false, None);
    let refresh_status_item = MenuItem::new("Refresh Status", true, None);
    let refresh_ip_item = MenuItem::new("Refresh IP", true, None);
    let ip_output_item = MenuItem::new("IP: (not refreshed yet)", true, None);
    let quit_item = MenuItem::new("Quit", true, None);

    menu.append(&status_item).expect("status menu item");
    menu.append(&PredefinedMenuItem::separator()).expect("separator");
    menu.append(&automatic_item).expect("automatic menu item");
    menu.append(&custom_item).expect("custom menu item");
    menu.append(&PredefinedMenuItem::separator()).expect("separator");
    menu.append(&refresh_status_item).expect("refresh status item");
    menu.append(&refresh_ip_item).expect("refresh ip item");
    menu.append(&ip_output_item).expect("ip output item");
    menu.append(&PredefinedMenuItem::separator()).expect("separator");
    menu.append(&quit_item).expect("quit item");

    let tray_icon = TrayIconBuilder::new()
        .with_menu(Box::new(menu))
        .with_tooltip(APP_TITLE)
        .with_icon(load_icon())
        .build()
        .expect("tray icon");

    let state = Arc::new(Mutex::new(AppState {
        worker_tx,
        handles: UiHandles {
            status_item,
            automatic_item,
            custom_item,
            refresh_status_item,
            refresh_ip_item,
            ip_output_item,
            quit_item,
        },
        busy: false,
    }));

    {
        let state = Arc::clone(&state);
        if let Ok(mut guard) = state.lock() {
            set_busy(&mut guard, true);
            let _ = guard.worker_tx.send(WorkerRequest::RefreshStatus);
        };
    }

    event_loop(state, tray_icon, response_rx);
}

fn spawn_worker(worker_rx: Receiver<WorkerRequest>, response_tx: Sender<WorkerResponse>) {
    thread::spawn(move || {
        while let Ok(request) = worker_rx.recv() {
            match request {
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
                    let _ = response_tx.send(action);
                    let status = refresh_status();
                    let _ = response_tx.send(WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    });
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
                    let _ = response_tx.send(action);
                    let status = refresh_status();
                    let _ = response_tx.send(WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    });
                }
                WorkerRequest::RefreshStatus => {
                    let status = refresh_status();
                    let _ = response_tx.send(WorkerResponse::StatusUpdated {
                        message: status.message,
                        mode: status.mode,
                    });
                }
                WorkerRequest::RefreshIp => {
                    let response = match ddns::refresh_ip() {
                        Ok(output) => WorkerResponse::IpRefreshed { output },
                        Err(error) => WorkerResponse::IpRefreshed {
                            output: format!("Error: {error}"),
                        },
                    };
                    let _ = response_tx.send(response);
                }
            }
        }
    });
}

fn event_loop(
    state: Arc<Mutex<AppState>>,
    _tray_icon: TrayIcon,
    response_rx: Receiver<WorkerResponse>,
) {
    loop {
        while let Ok(response) = response_rx.try_recv() {
            if let Ok(mut guard) = state.lock() {
                apply_worker_response(&mut guard, response);
            }
        }

        if let Ok(event) = MenuEvent::receiver().try_recv() {
            if let Ok(mut guard) = state.lock() {
                if guard.busy {
                    continue;
                }

                if event.id == guard.handles.automatic_item.id() {
                    set_busy(&mut guard, true);
                    let _ = guard.worker_tx.send(WorkerRequest::ApplyAutomatic);
                } else if event.id == guard.handles.custom_item.id() {
                    set_busy(&mut guard, true);
                    let _ = guard.worker_tx.send(WorkerRequest::ApplyCustom);
                } else if event.id == guard.handles.refresh_status_item.id() {
                    set_busy(&mut guard, true);
                    let _ = guard.worker_tx.send(WorkerRequest::RefreshStatus);
                } else if event.id == guard.handles.refresh_ip_item.id() {
                    set_busy(&mut guard, true);
                    guard.handles.ip_output_item.set_text("IP: Refreshing...");
                    let _ = guard.worker_tx.send(WorkerRequest::RefreshIp);
                } else if event.id == guard.handles.quit_item.id() {
                    std::process::exit(0);
                }
            }
        }

        let _ = TrayIconEvent::receiver().try_recv();
        while gtk::events_pending() != 0 {
            gtk::main_iteration_do(false);
        }
        gtk::main_iteration_do(false);
    }
}

fn init_gtk() {
    if std::env::var_os("DISPLAY").is_none() && std::env::var_os("WAYLAND_DISPLAY").is_none() {
        eprintln!(
            "Error: no graphical session (DISPLAY/WAYLAND_DISPLAY not set).\n\
             Run: ./native run   (from the linux folder on this machine)"
        );
        std::process::exit(1);
    }

    gtk::init().expect("Failed to initialize GTK");
}

fn apply_worker_response(state: &mut AppState, response: WorkerResponse) {
    match response {
        WorkerResponse::StatusUpdated { message, mode } => {
            state.handles.status_item.set_text(&message);
            state.handles.automatic_item.set_checked(mode == DnsMode::Automatic);
            state.handles.custom_item.set_checked(mode == DnsMode::Custom);
            set_busy(state, false);
        }
        WorkerResponse::ActionMessage { message, success } => {
            if success {
                state.handles.status_item.set_text(&message);
            } else {
                let failed = format!("Failed: {message}");
                state.handles.status_item.set_text(&failed);
            }
            set_busy(state, false);
        }
        WorkerResponse::IpRefreshed { output } => {
            state
                .handles
                .ip_output_item
                .set_text(&format!("IP: {output}"));
            set_busy(state, false);
        }
    }
}

fn set_busy(state: &mut AppState, busy: bool) {
    state.busy = busy;
    let enabled = !busy;
    state.handles.automatic_item.set_enabled(enabled);
    state.handles.custom_item.set_enabled(enabled);
    state.handles.refresh_status_item.set_enabled(enabled);
    state.handles.refresh_ip_item.set_enabled(enabled);
}

fn load_icon() -> tray_icon::Icon {
    let mut rgba = Vec::with_capacity(32 * 32 * 4);
    for y in 0..32 {
        for x in 0..32 {
            let dx = x as i32 - 15;
            let dy = y as i32 - 15;
            let dist = ((dx * dx + dy * dy) as f32).sqrt();
            if dist <= 12.0 {
                rgba.extend_from_slice(&[46, 125, 255, 255]);
            } else if dist <= 14.0 {
                rgba.extend_from_slice(&[20, 70, 160, 255]);
            } else {
                rgba.extend_from_slice(&[0, 0, 0, 0]);
            }
        }
    }

    tray_icon::Icon::from_rgba(rgba, 32, 32).expect("tray icon")
}
