%define product slingshot
%define component utils
%define component_prefix /opt/%{product}/%{component}
%define _build_id %{version}-%{release}
%define _prefix %{component_prefix}/%{_build_id}

Name: %{product}-%{component}
Version: 2.1.0
Release: %(echo ${BUILD_METADATA})
Group: System Environment/Libraries
License: BSD
Url: http://www.hpe.com
Source: %{name}-%{version}.tar.gz
Vendor: Hewlett Packard Enterprise Company
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch: noarch
Packager: Hewlett Packard Enterprise Company
Summary: Slingshot Utilities
Distribution: Slingshot

%description
Slingshot Network config

%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}

install -D -m 0755 bin/slingshot-utils %{buildroot}/%{_prefix}/bin/slingshot-utils
install -D -m 0755 bin/slingshot-snapshot.sh %{buildroot}/%{_prefix}/bin/slingshot-snapshot
install -D -m 0755 bin/slingshot-diag.sh %{buildroot}/%{_prefix}/bin/slingshot-diag

%clean
rm -rf %{buildroot}

%post
SH_PREFIX=%{_prefix}
# replace version number with default
SH_PREFIX_DEFAULT="${SH_PREFIX%/%{_build_id}}/default"
rm -f ${SH_PREFIX_DEFAULT}
ln -s %{_prefix} ${SH_PREFIX_DEFAULT}

SH_BINDIR=%{_bindir}
SH_BINDIR_DEFAULT=${SH_BINDIR/%{_build_id}/default}
ln -sf ${SH_BINDIR_DEFAULT}/slingshot-utils /usr/bin/slingshot-utils
ln -sf ${SH_BINDIR_DEFAULT}/slingshot-snapshot /usr/bin/slingshot-snapshot
ln -sf ${SH_BINDIR_DEFAULT}/slingshot-diag /usr/bin/slingshot-diag

%postun
rm -rf %{_prefix}
SH_PREFIX=%{_prefix}
SH_PREFIX_BASE=${SH_PREFIX%/%{_build_id}}
# replace version number with default
SH_PREFIX_DEFAULT=${SH_PREFIX_BASE}/default
if [ "$(ls -l ${SH_PREFIX_DEFAULT} 2>/dev/null | sed 's#.*/##')" == "%{_build_id}" ]; then
    # if this is the active instance of the package then we delete the default symlinks
    rm -f ${SH_PREFIX_DEFAULT}
    # if previous versions exist then find the latest
    SH_LAST=$(ls -r ${SH_PREFIX_BASE} | grep -E '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if [ ${#SH_LAST} -eq 0 ]; then
        # This is the last instance of the package so we delete all the symlinks
        rm -f /usr/bin/slingshot-utils
        rm -f /usr/bin/slingshot-snapshot
        rm -f /usr/bin/slingshot-diag
        # delete the directories (if empty)
        rmdir ${SH_PREFIX_BASE} 2>/dev/null || true
        rmdir ${SH_PREFIX_BASE%/%{name}} 2>/dev/null || true
    else
        # a previous verion exists, make previous actve with idefault symlink
        ln -s ${SH_PREFIX_BASE}/${SH_LAST} ${SH_PREFIX_DEFAULT}
    fi
fi


%files
%defattr(-,root,root,-)
%{_prefix}/bin/slingshot-utils
%{_prefix}/bin/slingshot-snapshot
%{_prefix}/bin/slingshot-diag
%doc COPYING

%changelog
