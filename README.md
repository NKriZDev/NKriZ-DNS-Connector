# NKriZ DNS Connector

Menu bar macOS app to switch DNS between automatic (DHCP) and NKriZ DNS servers.

## Custom DNS

- Primary: `178.22.122.101`
- Secondary: `185.51.200.1`

## Install

Double-click `dist/NKriZ-DNS-Connector-1.0.0.pkg` and follow the installer. The app is installed to `/Applications` and launches automatically.

Alternatively, open `dist/NKriZ-DNS-Connector-1.0.0.dmg` and drag the app to Applications.

## Usage

1. Click the network icon in the menu bar.
2. Choose **Automatic (DHCP)** or **NKriZ DNS**.
3. Enter your administrator password when prompted.

The app updates DNS on all enabled network interfaces (Wi-Fi, Ethernet, etc.).

## Build

```bash
chmod +x scripts/build-and-package.sh
./scripts/build-and-package.sh
```

Outputs:

- `build/Release/NKriZ DNS Connector.app`
- `dist/NKriZ-DNS-Connector-1.0.0.pkg`
- `dist/NKriZ-DNS-Connector-1.0.0.dmg`
