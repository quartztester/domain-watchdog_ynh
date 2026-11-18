The app needs to be installed at the root of a dedicated domain: the frontend hardcodes the `/api` base URL, so sub-path installs do not work.

Registration is disabled at install. To create additional app accounts, run a migration-safe password hash and SQL insert as documented in the app README, or enable and use the app's own API (`POST /api/register`).

Outgoing notifications (expiration emails) are sent through the box's Postfix with sender `domain-watchdog@<install-domain>`.

Redis runs as a private per-instance server (`<app>-redis.service`) and the message queue worker as `<app>-worker.service`; a third unit (`<app>-scheduler.service`) triggers watchlist processing every 5 minutes, mirroring the upstream deployment. Logs are in the systemd journal (`journalctl -u <app>-worker`).
