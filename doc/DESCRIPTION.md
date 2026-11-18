Domain Watchdog monitors domain names using RDAP, keeps their history and helps you acquire them when they expire.

Users create watchlists of domains; a worker polls the relevant RDAP servers, records status changes (expiration, transfer, deletion, ...) and can notify via email or webhooks.

Accounts are local to the app (email + password). No LDAP or SSO is available upstream; the app is gated behind the YunoHost portal. The first account is created at install for the selected admin user, using their YunoHost email and the password given at install.
