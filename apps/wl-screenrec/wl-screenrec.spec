%global debug_package %{nil}
Name: wl-screenrec
Version: 0.3.1
Release: 1.local%{?dist}
Summary: Wayland screen recorder with hardware encoding
License: Apache-2.0
URL: https://github.com/rosalyntg/wl-screenrec
Source0: wl-screenrec-%{version}.tar.gz
BuildRequires: cargo, clang, gcc, libdrm-devel, freeglut-devel, ffmpeg-free-devel, pkgconf-pkg-config

%description
Wayland screen recorder built from upstream v0.3.1 for Fedora 45 and FFmpeg 9.

%prep
%autosetup

%build
cargo build --release --locked -j4

%install
install -Dpm0755 target/release/wl-screenrec %{buildroot}%{_bindir}/wl-screenrec

%files
%license LICENSE
%{_bindir}/wl-screenrec
