# Troubleshooting

Issues we hit during development, and fixes that worked.

## KasmVNC

### "Could not start Xvnc — Unrecognized option: -MaxConnectionTime"

RealVNC is pre-installed on Pi OS and its `Xvnc` binary shadows KasmVNC's.
Module 06 already handles this by removing RealVNC. If it comes back via an
update, run:

```bash
sudo apt remove --purge realvnc-vnc-server realvnc-vnc-viewer
sudo apt install --reinstall ./kasmvncserver_trixie_*.deb
```

### Black screen / no taskbar after connecting

Default `xstartup` calls `lxsession` (generic) which doesn't load Pi OS's
desktop. You need the Pi-specific session profile. The template ships with:

```sh
exec dbus-launch --exit-with-session lxsession -s rpd-x -e LXDE
```

### `dbus-launch: not found` in xstartup log

Module 01 installs `dbus-x11`. If you skipped it:

```bash
sudo apt install -y dbus-x11
```

### `/etc/ssl/private/ssl-cert-snakeoil.key: certificate file doesn't exist`

The systemd user manager doesn't have `ssl-cert` group access at boot. The
template avoids this by pointing KasmVNC at user-owned cert files in
`~/.vnc/`. Module 07 installs the Let's Encrypt cert there.

### `/tmp/.X1-lock` left behind, service fails to start

Already handled by the service unit:

```
ExecStartPre=-/usr/bin/rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
```

## Bluetooth

### `bluetoothctl pair MAC` succeeds but `Paired: no`

No pairing agent is registered. We run `bt-agent --capability=NoInputNoOutput`
as a user systemd service (module 09). Verify:

```bash
systemctl --user is-active bt-agent.service
```

### Tesla refuses to add the Pi as a media device

Tesla checks the device class. The default Pi class is "computer", which
Tesla won't accept as an audio source. Module 09 sets it to `0x5A020C`
(smartphone + audio + telephony). If your car still refuses, try:

- `0x40020C` (phone, less services advertised)
- `0x200408` (phone, mobile)

Edit `/etc/bluetooth/main.conf`, restart `bluetooth.service`.

### "BT button doesn't open the app — pcmanfm asks Execute / Run in Terminal"

Module 10 sets `quick_exec=1` in `~/.config/libfm/libfm.conf` and marks the
`.desktop` file trusted. If a future libfm update resets the file, repeat the
sed in module 10.

## Network / hotspot detection

### Carrier still detected hotspot use

Verify TTL=65 is actually applied:

```bash
sudo tcpdump -nn -v -i eth1 -c 5 'tcp port 443'
# Should show "ttl 65" on outgoing packets.
```

If TTL is 64, the rule didn't load:

```bash
sudo nft list table inet ttlfix
sudo systemctl restart nftables
```

Some carriers also detect via:

- IPv6 (HopLimit). Module 04 disables IPv6 on the tether interface.
- DNS lookups to known tether-detection endpoints. Not addressed here.
- Browser User-Agent of the hotspot client (rare, unreliable detection).

### Mac on home Wi-Fi *and* PiTesla resolves wrong

macOS uses the highest-priority service's DNS for `nslookup`. To force
PiTesla as primary, drag it to the top of *System Settings → Network →
Set Service Order*, or temporarily disable the home connection.

## DNS hijack

### `pi.your.domain` doesn't resolve from a hotspot client

Hotspot dnsmasq overrides only apply for clients that use the Pi as their
DNS server. Verify the client got `10.42.0.1` as DNS via DHCP. From the Pi:

```bash
sudo cat /var/lib/NetworkManager/dnsmasq-wlan0.leases
```

Lease entries should show clients with the right IP range.

If your override isn't applied, restart the hotspot:

```bash
sudo nmcli connection down pi-hotspot
sudo nmcli connection up pi-hotspot
```

### Mac says `DNS_PROBE_FINISHED_NXDOMAIN`, Tesla says `ERR_CONNECTION_REFUSED`

Both symptoms point at the same root cause: the browser is doing DNS over
HTTPS (Tesla's Chromium, macOS iCloud Private Relay, Chrome's secure DNS)
and asking a *public* resolver, not the Pi. The public answer is
`NXDOMAIN` because no public record exists for the name. Tesla's
"REFUSED" variant is just an artifact of stale local fallback / HTTP retry
on top of that.

Fix: publish a public A record at Cloudflare for the hostname pointing at
the Pi's hotspot IP (`10.42.0.1`), DNS-only / proxy off. Once it
propagates (TTL 60s), both `nslookup pi.your.domain` against a public
resolver and the Pi's own dnsmasq return the same answer.

```bash
# Sanity check from any machine:
nslookup pi.your.domain 1.1.1.1
# ;; ANSWER: pi.your.domain. 60 IN A 10.42.0.1
```

## HTTPS leakage / certificate errors

### Every HTTPS site from a hotspot client shows CN mismatch (`NET::ERR_CERT_COMMON_NAME_INVALID`)

The :443 → :8443 nftables redirect was previously too broad: it had no
destination filter, so any 443 packet *forwarded* through the Pi was also
redirected to KasmVNC. The browser then saw the Pi's
`pi.your.domain` certificate for unrelated sites.

Already fixed in `templates/port-redirect.nft`:

```nft
fib daddr type local tcp dport 443 redirect to :8443
```

`fib daddr type local` matches only packets whose destination address
belongs to this host. If you're on an older checkout, rerun module 05.

### Tesla browser: `ERR_CONNECTION_REFUSED` on `pi.your.domain`, but Mac is fine

Tesla's Chromium tries `http://` before `https://` when no HSTS entry
exists. With nothing on :80 the kernel sends TCP RST and the browser
shows REFUSED. Modern Chrome/macOS use HTTPS-First and never see this.

Module 05 now ships a tiny Python redirector on :80 that returns
`301 → https://`. Verify:

```bash
systemctl status http-redirect.service
curl -sI http://pi.your.domain   # expect: HTTP/1.0 301 + Location: https://...
```

### Let's Encrypt issuance fails with "DNS problem"

Cloudflare token might lack edit permission on the zone. Re-create with
"Edit zone DNS" template, *Specific zone* set to your domain. Account ID is
usually unnecessary with scoped tokens — leave `CF_ACCOUNT_ID=""`.
