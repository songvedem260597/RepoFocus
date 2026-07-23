# RepoFocus Windows UI reference

These screenshots capture RepoFocus `0.11.0 (19)` on July 24, 2026 for use while implementing the Windows version.

## Capture specification

- Window content: `1180 × 760` logical points
- PNG size: `2360 × 1520` pixels (`@2x`)
- Language: English
- Themes: Light and neutral-charcoal Dark
- Data: Live repository data from the connected account
- Scope: Only the RepoFocus window is captured; the desktop and other applications are excluded

## Light theme

| Tab | Screenshot |
| --- | --- |
| Focus | [01-focus.png](light/01-focus.png) |
| Activity | [02-activity.png](light/02-activity.png) |
| All Repositories | [03-all-repositories.png](light/03-all-repositories.png) |
| Needs Attention | [04-needs-attention.png](light/04-needs-attention.png) |
| Completed | [05-completed.png](light/05-completed.png) |
| Settings | [06-settings.png](light/06-settings.png) |

## Dark theme

| Tab | Screenshot |
| --- | --- |
| Focus | [01-focus.png](dark/01-focus.png) |
| Activity | [02-activity.png](dark/02-activity.png) |
| All Repositories | [03-all-repositories.png](dark/03-all-repositories.png) |
| Needs Attention | [04-needs-attention.png](dark/04-needs-attention.png) |
| Completed | [05-completed.png](dark/05-completed.png) |
| Settings | [06-settings.png](dark/06-settings.png) |

## Windows implementation notes

- Preserve the three-column hierarchy: navigation sidebar, repository/activity content, and contextual inspector.
- Keep the existing spacing rhythm (`4 / 8 / 12 / 16 / 24`) and compact 7–10 px corner radii.
- Replace the macOS traffic-light window controls with native Windows title-bar behavior; do not reproduce macOS window chrome.
- Preserve the semantic colors and contrast in both themes, especially Git status badges, progress states, selection backgrounds, borders, and empty states.
- Use Segoe UI or the system UI font on Windows while keeping the same visual weight and information hierarchy.
- Maintain the custom field, date, checkbox, segmented-control, and button styling rather than falling back to unstyled platform inputs.
