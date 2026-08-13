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
if [[ -d ${HOME}/.cargo/bin ]]; then
  path+=("${HOME}/.cargo/bin")
fi
# for fzf not installed via a package
if [[ -d ${HOME}/.fzf ]]; then
  path+=("${HOME}/.fzf/bin")
fi
export PATH
