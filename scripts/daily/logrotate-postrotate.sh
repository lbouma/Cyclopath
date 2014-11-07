#!/bin/bash
#
# See: ccpdev/private/runic/etc/logrotate.d/cyclopath
#
# Our config will cause logrotate to do the following for a log file,
# e.g., some.log: delete some.log.3.gz
#                 mv some.log.2.gz to some.log.3.gz,
#                 compress some.log.1 to some.log.2.gz
#                 mv some.log to some.log.1
# Since apache needs to reload before some.log.1 is done being writ,
# we won't compress it until the next time we rotate this log file.
# So make a backup of the some.log.2.gz file, which is the newly
# created backup. So we'll keep historic copies of most log files,
# except the one just rotated and the current logfile.
#
# The script arg is, e.g., /ccp/var/log/testing/minnesota-mr_do.log.1
log_path=$1
#echo "============== ${log_path}"
rotated_log=$(basename $log_path)
log_relbase=$(dirname $log_path)

# Remove ".1".
# E.g., "minnesota-apache.log.1" => "minnesota-apache.log"
# See "Parameter Expansion" in `man bash` for more tricks.
log_name=${rotated_log%.1}

# Make the name of the last gzipped archive that logrotate made.
second_to_last=${log_relbase}/${log_name}.2.gz

# Figure out the owner of the archive.
if [[ `basename $log_relbase` = 'pyserver' ]]; then
  if [[ "`cat /proc/version | grep Ubuntu`" ]]; then
    # Ubuntu
    owner_d='www-data'
  elif [[ "`cat /proc/version | grep Red\ Hat`" ]]; then
    # echo Red Hat
    owner_d='apache'
  else
    echo "ERROR: Unexpected OS: Cannot determine httpd user."
    exit 1
  fi
elif [[ `basename $log_relbase` = 'postgresql' ]]; then
  owner_d='postgresql'
else
  echo "ERROR: Unknown log file being processed."
  exit 1
fi

# If the last gzipped archive exists, stow it away so logrotate
# doesn't clobber it.
if [[ -f "${second_to_last}" ]]; then
   # Use stat to make a filename based on the date.
   caldate=`stat -c %y ${second_to_last} | /bin/sed -r 's/^([-0-9]+).*$/\1/'`
   # Make sure the archive location exists.
   bkup_dir=${log_relbase}/archive/${log_name}
   /bin/mkdir -p ${bkup_dir}
   /bin/chown ${owner_d} ${log_relbase}/archive
   /bin/chmod 2775 ${log_relbase}/archive
   /bin/chown ${owner_d} ${bkup_dir}
   /bin/chmod 2775 ${bkup_dir}
   #backup_file=${log_relbase}/archive-logcheck/${log_name}-${caldate}.gz
   backup_file=${bkup_dir}/${caldate}.gz
   /bin/cp -f ${second_to_last} ${backup_file}
fi

# Remove the offset file so we don't get the annoying tampering warning email.
#
#^*** WARNING ***: Log file /foo/bar.log is smaller than last time checked!
#^***************
#^*************** This could indicate tampering.
#
try1="/var/lib/logcheck/offset.export.scratch.ccp.var.log.pyserver.${log_name}"
try2="/var/lib/logcheck/offset.export.scratch.ccp.var.log.postgresql.${log_name}"
if [[ -f ${try1} ]]; then
  /bin/rm -f ${try1}
fi
if [[ -f ${try2} ]]; then
  /bin/rm -f ${try2}
fi

