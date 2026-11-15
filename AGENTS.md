# Repository hygiene

Keep generated screenshots, animations, render frames, preview reports, logs,
temporary environments, downloaded reference repositories, and build caches
outside this checkout. Use a task directory under `~/.cache/agent-desktops/` or
another external temporary/cache directory. Do not create ad-hoc `work/`,
`artifacts/`, or preview-output directories inside this repository.

Run Python checks with `PYTHONDONTWRITEBYTECODE=1`, or use an external
`PYTHONPYCACHEPREFIX`, so checks do not leave bytecode in the checkout. Keep only
intentional configuration, documentation, source assets, and reusable test
fixtures here. Do not hide generated preview artifacts with ignore rules.

# GUI isolation

For agent-owned Linux GUI tests, diagnostics, screenshots, and automation, read
and use [isolated-gui](codex/skills/isolated-gui/SKILL.md). Run these tasks on the
helper's private display and D-Bus session, including GTK/WebKit tests that
create windows. Never fall back to the inherited display or session bus if
isolation fails. Explicit requests to control the user's existing app or browser
tab remain scoped to that app or tab. Respect application launch restrictions
and use fixtures or separate profiles where needed.
