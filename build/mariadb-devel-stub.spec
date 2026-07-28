# Build-environment plumbing. Never published.
#
# The Dovecot project's EL9 spec carries `BuildRequires: mariadb-devel`. AL2023
# has no package of that name and nothing provides it. Publishing mariadb-devel
# is out of the scope for this project, but with this stub you should be able to
# use mariadb if you get it installed on AL2023.
# #
# This stub provides that name and pulls in the package that actually carries the
# headers, which keeps the Dovecot spec unedited and leaves dependency checking on
# for every other BuildRequires — which `rpmbuild --nodeps` would not.

%global stub_version %{?connector_version}%{!?connector_version:3.1.13}

Name:           al2023-mariadb-devel-compat
Version:        %{stub_version}
Release:        1%{?dist}
Summary:        Build-only compatibility provider for mariadb-devel on AL2023
License:        MIT
BuildArch:      noarch

Provides:       mariadb-devel = %{version}-%{release}
Requires:       mariadb-connector-c-devel

%description
Satisfies `BuildRequires: mariadb-devel` on Amazon Linux 2023 by mapping it onto
mariadb-connector-c-devel, which ships the MariaDB client headers, mysql_config
and pkgconfig(libmariadb). Contains no files. Build environment only — this
package is never published or installed on a consumer host.

%files

%changelog
* Tue Jul 28 2026 dovecot.2.4.ALinux2023 - 0-1
- Initial stub.
