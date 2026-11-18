# domain-watchdog — packaging design

Symfony 7.3 / PHP 8.4 app with a React SPA front. The SPA hardcodes `baseURL: '/api'`
(assets/utils/api/index.ts), which forces a full-domain, root-path install.

Anything not mentioned below is standard YunoHost boilerplate identical in most packages.

## Lifecycle
- **Install:** questions → source tarball → composer install (`--no-scripts`) → .env/redis render →
  JWT keypair + doctrine migrations + admin INSERT → yarn build → fpm/nginx/units →
  worker gate → RDAP seed message.
- **Upgrade:** full_replace of sources keeping `.env.local`, `.env.local.php`, `config/jwt`,
  `public/content`, `.composer` (scripts/upgrade L35); migrations re-run; everything else as install.
- **Backup/restore:** install_dir + data_dir + pg dump + confs/units archived; nothing regenerated
  on restore except unit enable; restore ends with an nginx reload (scripts/restore L52).

## Decisions
- **Source:** GitHub tag tarball v1.4.6 pinned by sha256; `autoupdate.strategy = latest_github_tag`
  (manifest.toml L51-L52). Upstream ships no release assets.
- **Runtime:** apt PHP 8.4 from sury (pre-seeded in bookworm appci; bookworm stock is 8.2) via
  `[resources.apt]` php8.4-* packages; node 22 via nodejs resource; composer 2.11.2 pinned
  (scripts/_common.sh L16); yarn pinned to classic 1.x through corepack (scripts/_common.sh L24).
- **Services:** three units beyond fpm: `<app>-redis` (private redis), `<app>-worker`
  (messenger:consume, conf/worker.service L12), `<app>-scheduler` (conf/scheduler.service L14:
  upstream's Symfony scheduler is not registered in bundles.php, so the unit loops
  `app:process-watchlist` every 300 s like the documented deployment).
- **Storage:** PostgreSQL via database resource (serverVersion=15, bookworm's candidate);
  private redis on a booked loopback port, `requirepass` from settings, RDB under $data_dir/redis;
  noeviction protects messenger keys.
- **Auth:** ldap/sso false — upstream supports only its own email+password (JWT cookie) or an
  external generic OAuth2 client; no LDAP/header auth paths. Admin app account is INSERTed at
  install with `password_hash()` bcrypt matching the app's `auto` hasher and `ON CONFLICT DO NOTHING`
  for idempotency (scripts/_common.sh L41-L47). Portal permission gates the whole app.
- **Email:** box's Postfix, `smtp://127.0.0.1:25` no auth, sender `<app>@<domain>` (conf/env.local L18-L20);
  registration and email verification disabled (conf/env.local L22-L23).
- **Path:** root-only, enforced structurally: no `[install.path]` question, nginx template hardcodes
  `location /` (conf/nginx.conf L1).
- **Ports/firewall:** `[resources.ports.redis]` random, loopback-bound; nothing exposed.
- **Scheduler:** the `<app>-scheduler` loop unit above; no cron.
- **Migration:** standard full_replace upgrade; secrets live in app settings and configs re-render
  from them (jwt_passphrase default-init in upgrade L23 guards legacy installs).
- **Sandboxing:** example_ynh baseline on all three units; worker/scheduler additionally need
  AF_NETLINK; no relaxations below baseline.
- **Backup:** DB dump + both dirs + pool/nginx/unit files; redis RDB rides inside data_dir (bgsave
  skipped: 5-min watchlist runs make any recent state re-derivable from RDAP).
- **Admin-surface:** no config panel; `yunohost service list` shows the worker; logs in journal.

## Don't break
- FPM extra config must keep `php_admin_value[...]` prefixes — bare ini lines break pool parsing
  (conf/extra_php-fpm.conf L6).
- Every `bin/console` call merges stderr into stdout (`2>&1`) — Symfony deprecation floods are
  counted as warnings and abort CI (scripts/_common.sh L11).
- The worker must be started exactly once with the wait_until gate; a plain start followed by a
  gated start re-triggers restart and the journal-tail race fails install (scripts/_common.sh L68-L71).
- `[resources.ports.redis]` must stay empty-valued; `default = 0` books port 0 and redis exits
  "not listen anywhere" (manifest.toml L64).
- Restore must end with the nginx reload (scripts/restore L52) or backup_restore lands on the
  default nginx page on the fresh-system check.
- `env[APP_ENV]`/`env[APP_DEBUG]` in the pool (conf/extra_php-fpm.conf L2-L3): belt-and-suspenders
  pinning prod for fpm requests; the compiled `.env.local.php` already carries `APP_ENV=prod`.
- yarn is pinned `corepack yarn@1` (lockfile is yarn-1); node 22 corepack defaults break `yarn install` otherwise.
