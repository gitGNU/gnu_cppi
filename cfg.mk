# -*- makefile -*-
## Customize maint.mk.

# Use alpha.gnu.org for alpha and beta releases.
# Use ftp.gnu.org for major releases.
gnu_ftp_host-alpha = alpha
gnu_ftp_host-beta = alpha
gnu_ftp_host-major = ftp
gnu_rel_host = $(gnu_ftp_host-$(RELEASE_TYPE)).gnu.org

url_dir_list = \
  ftp://$(gnu_rel_host)/gnu/cppi \
  http://fetish.sf.net

local-checks-to-skip = patch-check strftime-check check-AUTHORS

# The GnuPG ID of the key used to sign the tarballs.
gpg_key_ID = D333CBA1

# Tests not to run as part of "make distcheck".
# Exclude changelog-check here so that there's less churn in ChangeLog
# files -- otherwise, you'd need to have the upcoming version number
# at the top of the file for each `make distcheck' run.
local-checks-to-skip += changelog-check
