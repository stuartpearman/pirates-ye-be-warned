# Cloud Server

This directory contains the VPS side of the public tunnel for the home services.

## Architecture

```text
Internet -> DNS example.com -> VPS Caddy :80/:443 -> frps HTTP vhost :8080 -> frpc at home -> local services
Internet -> DNS/IP :32400 -> VPS frps TCP proxy -> frpc at home -> home Plex :32400
```

Public services configured by default:

- `https://plex.example.com` -> home Plex `127.0.0.1:32400` through Caddy HTTPS
- `plex.example.com:32400` or `VPS_PUBLIC_IP:32400` -> home Plex `127.0.0.1:32400` through FRP TCP
- `nextcloud.example.com` -> home Nextcloud `127.0.0.1:8081`
- `jelly.example.com` -> home Jellyfin `127.0.0.1:8096`

Caddy and FRP are both needed for the HTTPS path. Caddy handles public certificates and host routing on `80`/`443`; FRP carries the request from the VPS back to the home server. Direct Plex port access uses FRP TCP directly and bypasses Caddy.

## DNS

Create DNS-only `A` records pointing at the VPS public IP:

```text
plex.example.com       A  203.0.113.10
nextcloud.example.com  A  203.0.113.10
jelly.example.com      A  203.0.113.10
```

A wildcard `*.example.com A 203.0.113.10` also works, but explicit records are clearer.

## Initial Ubuntu 24.04 Setup

Run on the VPS:

```bash
sudo cloud-server/scripts/setup-ubuntu-24.04.sh
```

Then either log out and back in if you add your user to the `docker` group manually, or keep using `sudo` for Docker commands.

## Start Cloud Stack

```bash
cd cloud-server
cp .env.example .env
editor .env
scripts/bootstrap-cloud.sh
```

Use a long random `FRP_AUTH_TOKEN`. The same token must be placed in the home server `.env`.

## Home Server Pairing

On the home server, set these values in the repo root `.env`:

```env
PUBLIC_DOMAIN=example.com
FRP_SERVER_ADDR=222.3.444.55
FRP_AUTH_TOKEN=same-token-as-cloud
PLEX_ADVERTISE_IP=https://plex.example.com,http://plex.example.com:32400,http://222.3.444.55:32400
```

Then run:

```bash
scripts/bootstrap-cloud-client.sh
docker compose --profile cloud-client up -d frpc
docker compose --profile cloud-client restart frpc
```

The restart is required when `frpc` is already running because the generated TOML is bind-mounted, but the process does not reload it automatically.

On the VPS, confirm Docker is publishing the direct Plex port after deployment:

```bash
docker compose ps frps
docker compose port frps 32400
```

## Verification

On the VPS:

```bash
docker compose ps
docker compose logs -f frps
```

From anywhere after DNS propagates and the home client is connected:

```bash
curl -I https://plex.example.com
curl -I http://plex.example.com:32400
curl -I http://203.0.113.10:32400
curl -I https://nextcloud.example.com
curl -I https://jelly.example.com
```