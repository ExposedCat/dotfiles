# Fedora f44 packaging: 90802c562a2f793a339408e2ea2d36d95cdc5b21
%global glib2_version 2.80.0
%global gcr_version 3.27.90
%global gcrypt_version 1.2.2

%bcond_without ssh_agent

Name:           gnome-keyring
Version:        50.0
Release:        2.mr112%{?dist}
Summary:        Framework for managing passwords and other secrets

%global tarball_version %%(echo %{version} | tr '~' '.')
%global major_version %%(cut -d "." -f 1 <<<%{tarball_version})

# egg/ is (GPL-2.0-or-later OR LGPL-3.0-or-later) OR BSD-3-Clause
# pkcs11/ is MPL-1.1 OR GPL-2.0-or-later OR  LGPL-2.1-or-later
License:        GPL-2.0-only AND GPL-2.0-or-later AND LGPL-2.1-or-later AND ((GPL-2.0-or-later OR LGPL-3.0-or-later) OR BSD-3-Clause) AND (MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later)
URL:            https://wiki.gnome.org/Projects/GnomeKeyring
Source0:        https://download.gnome.org/sources/%{name}/%{major_version}/%{name}-%{tarball_version}.tar.xz
# https://gitlab.gnome.org/GNOME/gnome-keyring/-/merge_requests/78
# https://gitlab.gnome.org/GNOME/gnome-keyring/-/issues/165
# https://bugzilla.redhat.com/show_bug.cgi?id=2349314
# Ensure the login collection is registered after unlocking
Patch:          78.patch
# Preserved in https://github.com/ExposedCat/gnome-keyring (main).
# GNOME MR !112, commits c06dd839 and 8fcdeffe.
Patch:          mr112.patch

BuildRequires:  pkgconfig(gcr-3) >= %{gcr_version}
BuildRequires:  pkgconfig(glib-2.0) >= %{glib2_version}
BuildRequires:  pkgconfig(libcap-ng)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(p11-kit-1)
BuildRequires:  docbook-dtds
BuildRequires:  docbook-style-xsl
BuildRequires:  dbus-daemon
BuildRequires:  gcc
BuildRequires:  gettext
BuildRequires:  git-core
BuildRequires:  intltool
BuildRequires:  libgcrypt-devel >= %{gcrypt_version}
BuildRequires:  libselinux-devel
BuildRequires:  meson
BuildRequires:  pam-devel
BuildRequires:  systemd-rpm-macros
%if %{with ssh_agent}
BuildRequires:  /usr/bin/ssh-add
BuildRequires:  /usr/bin/ssh-agent
%endif
BuildRequires:  /usr/bin/xsltproc

%if %{with ssh_agent}
Requires: /usr/bin/ssh-add
Requires: /usr/bin/ssh-agent
%endif
# for /usr/libexec/gcr-ssh-askpass
Requires: gcr3

%description
The gnome-keyring session daemon manages passwords and other types of
secrets for the user, storing them encrypted with a main password.
Applications can use the gnome-keyring library to integrate with the keyring.


%package pam
Summary: Pam module for unlocking keyrings
License: LGPL-2.1-or-later
Requires: %{name}%{?_isa} = %{version}-%{release}
# for /lib/security
Requires: pam%{?_isa}

%description pam
The gnome-keyring-pam package contains a pam module that can
automatically unlock the "login" keyring when the user logs in.


%prep
%autosetup -S git -n %{name}-%{tarball_version}


%build
%meson \
           -Dpam=true \
           -Dsystemd=enabled \
           -Dpkcs11-config=%{_datadir}/p11-kit/modules \
%if %{with ssh_agent}
           -Dssh-agent=true
%else
           -Dssh-agent=false
%endif

%meson_build


%install
%meson_install

%find_lang %{name}

%check
# The test daemons use fixtures and a private bus without service activation.
cat > test-bus.conf <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
env -u DISPLAY -u WAYLAND_DISPLAY -u GNOME_KEYRING_CONTROL -u SSH_AUTH_SOCK \
    /usr/bin/dbus-run-session --config-file="$PWD/test-bus.conf" -- \
    meson test -C %{_vpath_builddir} --no-rebuild --print-errorlogs

%post
%systemd_user_post gnome-keyring-daemon.service

%preun
%systemd_user_preun gnome-keyring-daemon.service

%files -f gnome-keyring.lang
%doc NEWS README
%license COPYING COPYING.LIB
# LGPL
%dir %{_libdir}/gnome-keyring
%dir %{_libdir}/gnome-keyring/devel
%{_libdir}/gnome-keyring/devel/*.so
%dir %{_libdir}/pkcs11
%{_libdir}/pkcs11/*.so
# GPL
%{_bindir}/gnome-keyring-daemon
%{_bindir}/gnome-keyring
%{_bindir}/gnome-keyring-3
%{_datadir}/dbus-1/services/*.service
%{_sysconfdir}/xdg/autostart/*
%{_datadir}/GConf/gsettings/*.convert
%{_datadir}/glib-2.0/schemas/*.gschema.xml
%{_datadir}/p11-kit/modules/gnome-keyring.module
%dir %{_datadir}/xdg-desktop-portal
%dir %{_datadir}/xdg-desktop-portal/portals
%{_datadir}/xdg-desktop-portal/portals/gnome-keyring.portal
%{_mandir}/man1/gnome-keyring.1*
%{_mandir}/man1/gnome-keyring-3.1*
%{_mandir}/man1/gnome-keyring-daemon.1*
%{_userunitdir}/gnome-keyring-daemon.service
%{_userunitdir}/gnome-keyring-daemon.socket

%files pam
%{_libdir}/security/*.so

%changelog
* Fri Sep 04 2026 Artem Prokop <artem13.prokop@gmail.com> - 50.0-2.mr112
- Apply upstream MR !112 to fix the Secret Service OpenSession race
