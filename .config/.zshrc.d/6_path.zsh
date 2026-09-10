typeset -U path
# for /usr/local includes
if [[ -d /usr/local/bin ]]; then
  path+=('/usr/local/bin')
fi
if [[ -d /usr/local/sbin ]]; then
  path+=('/usr/local/sbin')
fi

# adding in home bin/scripts path
if [[ -d ${HOME}/bin ]]; then
  path+=("${HOME}/bin")
fi
if [[ -d ${HOME}/scripts ]]; then
  path+=("${HOME}/scripts")
fi

if [[ ${MACOS} ]]; then
  if [[ -d /opt/homebrew/bin ]]; then
    path+=('/opt/homebrew/bin')
  fi
  if [[ -d /opt/homebrew/sbin ]]; then
    path+=('/opt/homebrew/sbin')
  fi

  # Homebrew's `make` formula is keg-only; its gnubin dir symlinks `make` to
  # `gmake`, so putting gnubin ahead of everything else resolves plain
  # `make` to GNU 4.x instead of the bundled /usr/bin/make (3.81).
  #
  # Prepend, not path+=: this file's existing idiom is append, which leaves
  # /usr/bin ahead of anything added -- verified this session:
  # `path+=` yields first=/usr/bin; `path=(dir $path)` yields first=.../gnubin.
  # An append here would be inert and would still look correct.
  #
  # Both Homebrew prefixes are tested for existence, never brew --prefix:
  # this file is what puts /opt/homebrew/bin on PATH in the first place, so
  # brew is not guaranteed resolvable here -- and a hardcoded /opt/homebrew
  # would silently no-op on the fleet's one x86_64 mac (ratna, Homebrew at
  # /usr/local, gnubin already present there per
  # docs/superpowers/specs/2026-08-12-gnu-make-4-on-macos-design.md).
  for _gnubin in "${_OVERRIDE_GNUBIN_ARM:-/opt/homebrew/opt/make/libexec/gnubin}" \
                 "${_OVERRIDE_GNUBIN_INTEL:-/usr/local/opt/make/libexec/gnubin}"; do
    [[ -d ${_gnubin} ]] && { path=(${_gnubin} $path); break }
  done
  unset _gnubin
fi

if [[ ${LINUX} ]]; then
  if [[ -d /opt/local/bin ]]; then
    path+=('/opt/local/bin')
  fi
  if [[ -d /opt/local/sbin ]]; then
    path+=('/opt/local/sbin')
  fi
  if [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then
    path+=('/home/linuxbrew/.linuxbrew/bin')
  fi
  if [[ -d /home/linuxbrew/.linuxbrew/sbin ]]; then
    path+=('/home/linuxbrew/.linuxbrew/sbin')
  fi
  if [[ -d ${HOME}/.local/bin ]]; then
    path+=("${HOME}/.local/bin")
  fi
  if [[ ${UBUNTU} ]]; then
    if [[ -d /usr/local/go/bin ]]; then
      path+=("/usr/local/go/bin")
    fi
    if [[ -d /snap/bin ]]; then
      path+=('/snap/bin')
    fi
  fi
fi
# Docker Desktop's CLI shims. `docker` and the credential helpers are
# symlinked into /usr/local/bin by the installer, but `docker-compose` is NOT
# -- verified 2026-09-10: it resolves only via this directory, so dropping the
# entry loses compose and nothing else.
#
# This lives here rather than in .zprofile, where Docker Desktop's installer
# writes it on every upgrade. Two reasons. The installer hardcodes an absolute
# /Users/<name>, and .zprofile is symlinked onto six other machines including
# Linux, where that path is meaningless. And a tracked dotfile an installer
# rewrites is drift nobody notices.
#
# The move is a deliberate NARROWING of actor scope: .zshrc.d is sourced by
# .zshrc, so this reaches interactive shells only, while .zprofile reaches
# every login shell and its descendants. Nothing in this repo invokes
# docker-compose non-interactively -- lib/linux_ubuntu.sh's callers are Linux
# install paths that never see ~/.docker/bin -- so the narrowing costs nothing
# here. It is the same mechanism that makes brew unreachable to a
# non-interactive setup_env.sh on the workstation; if a cron job or a script
# ever needs compose, this is the line that will not be on its PATH.
#
# Seam, not a bare path: ~/.docker/bin exists on any mac running Docker
# Desktop, so a test for the absent branch would short-circuit on the real
# directory and assert nothing -- the same reason the gnubin overrides above
# exist.
#
# Appended, not prepended, matching what the installer did: /usr/local/bin's
# docker keeps winning, so this changes no existing resolution.
if [[ ${HAS_DOCKER} ]]; then
  _docker_bin="${_OVERRIDE_DOCKER_BIN:-${HOME}/.docker/bin}"
  [[ -d ${_docker_bin} ]] && path+=("${_docker_bin}")
  unset _docker_bin
fi

if [[ -d ${HOME}/.cargo/bin ]]; then
  path+=("${HOME}/.cargo/bin")
fi
# for fzf not installed via a package
if [[ -d ${HOME}/.fzf ]]; then
  path+=("${HOME}/.fzf/bin")
fi
export PATH
