#!/bin/bash

# *** Helper fcns.

# ***

# Create a directory and set its permissions and user and group.
ccp_mkdir () {
  if [[ -z "$1" ]]; then
    echo "ccp_mkdir: error: expecting directory name as first arg."
    exit 1
  fi
  if [[ -e $1 ]]; then
    if ! [[ -d $1 ]]; then
      echo "ccp_mkdir: error: $1 exists but not a directory."
      exit 1
    else
      #echo "ccp_mkdir: skipping: $1 [already exists]"
      : # null command; NOP; noop
    fi
  else
    #echo "ccp_mkdir: creating: $1 [new directory]"
    mkdir -p $1
  fi
  # NOTE: Just changing perms on the folder. If it already exists, we're not
  # doing it recursively.
  sudo chmod 2775 $1
  sudo chown $targetuser $1
  sudo chgrp $targetgroup $1
} # end of ccp_mkdir

#export -f ccp_mkdir()

# ***

# Generate a system file from an m4 template and install it, possibly asking
# user to overwrite it if it exists and is different.
system_file_diff_n_replace () {
  # Usage: $0 file_path template_name [base_path [m4_args]]
  if [[ -z "$1" || -z "$2" ]]; then
    echo
    echo "Error: Silly programmer. You forgot the path and/or filename!"
    return
    exit 1
  fi
  file_path=$1
  template_name=$2
  if [[ -z "$3" ]]; then
    base_path=$template_name
    ccp_target=$template_name
  else
    if [[ -z "$3" || -z "$4" ]]; then
      echo
      echo "Error: Missing the base path and/or target path."
      return
      exit 1
    fi
    base_path=$3 # e.g., sites-available/cyclopath or ../maintenance
    ccp_target=$4 # e.g., ln -s ... /ccp/dev/cp/
    # MAGIC_NUMBER: shift n, i.e., the number of preceeding args.
    shift 4
    # The argvs, >= 5, are sent to m4.
    more_m4_defines=$*
  fi
  #
  # Generate the new file and diff against what's already installed.
  #
  # Start by making a temporary location for the intermediate file.
  RANDOM_NAME="`uuidgen`"
  RANDOM_NAME=/tmp/ccp_setup_sysfiles_$RANDOM_NAME
  mkdir $RANDOM_NAME
  # Generate the intermediate file.
  m4 \
    $ccp_m4_defines \
    --define=CCPBASEDIR=$ccp_target \
    $more_m4_defines \
    ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_TARGET}/${file_path}/${template_name} \
      > ${RANDOM_NAME}/${base_path}
  # Compare the default and generated files against what's on the system.
  do_copy_file=1
  echo -n "Examining system file: /${file_path}/${base_path}... "
  if ! [[ -e "/${file_path}/${base_path}" ]]; then
    echo "does not exist (yet)."
    # Leave do_copy_file=1
  # else, see if the existing file is the same as the default system file
  elif [[ "" != "`diff /${file_path}/${base_path} \
      ${AO_TEMPLATE_BASE}/${CCPDEV_PSQL_SOURCE}/${file_path}/${base_path}`" ]];
    then
    # Differs from the default file that Ubuntu installs...
    echo -n "diffs from source... "
    if [[ "" != "`diff /${file_path}/${base_path} \
                      ${RANDOM_NAME}/${base_path}`" ]]; then
      # Differs from the default file that Cyclopath installs...
      echo "has been edited."
      echo
      echo "Warning: /${file_path}/${base_path} has been edited."
      echo
      echo "Here's the diff:"
      echo
      diff /${file_path}/${base_path} ${RANDOM_NAME}/${base_path}
      echo
      echo -n "Would you like to overwrite the existing file? (y/[N]) "
      read sure
      if [[ "$sure" != "y" && "$sure" != "Y" ]]; then
        echo "Warning: Skipping file: ${base_path}"
        do_copy_file=0
      fi
    else
      # The diff against the target shows nothing changed.
      echo "skipped (up to date)."
      do_copy_file=0
    fi
  # else, same as default system file, and do_copy_file=1
  fi
  if [[ $do_copy_file -ne 0 ]]; then
    # Nix the system file.
    sudo /bin/rm -f /${file_path}/${base_path}
    # Copy the newly-generated system file.
    sudo /bin/cp ${RANDOM_NAME}/${base_path} /${file_path}/${base_path}
    sudo chmod 664 /${file_path}/${base_path}
    sudo chown $targetuser /${file_path}/${base_path}
    sudo chgrp $targetgroup /${file_path}/${base_path}
    echo "replaced."
  fi

  # Cleanup.
  /bin/rm -rf $RANDOM_NAME

} # end of system_file_diff_n_replace

