# Offline Markdown editor

The editor uses ProseMirror, markdown-it 14.1.0 and KaTeX 0.16.22, bundled locally.
See THIRD-PARTY-LICENSES.txt for all bundled JavaScript versions and licenses.
KaTeX CSS and fonts are copied unmodified from its npm distribution.

Rebuild: `cd WebEditor && npm ci && npm run build` from the repository root.
The lockfile pins exact versions. No network or CDN is used at runtime.

Upstream: https://prosemirror.net/ · https://github.com/markdown-it/markdown-it · https://katex.org/
