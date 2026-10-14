---
name: server
description: Inspect deployed applications over SSH, including logs, databases, health, and process status. Use when the user mentions a server, deployment, or a production issue. Make fixes locally and deploy with pm3 only when instructed.
---

# Server

Unless stated otherwise, “deployed on a server” means deployed to
`kitkat@server.local` over SSH and managed by **pm3**. Use `pm3`, never `pm2`.

Use this skill to analyze logs, inspect application and process status, check
health endpoints, query databases, and investigate resource usage or deployment
failures. Keep remote diagnostics read-only, including database queries.

Never edit files, configuration, code, or database contents directly on the
server unless stated otherwise. Make and verify all changes in the local checkout, then follow the
user's instructions for committing, pushing, and deploying.

After the changes are pushed, restart the relevant app with `pm3 restart -d`
only when the user instructs you to deploy or restart. This command automatically
fetches Git changes and restarts the app; do not run a separate remote Git pull
or copy local files onto the server. Check `pm3 --help` for app selection syntax
if needed, then verify status, health, and recent logs after the restart.
