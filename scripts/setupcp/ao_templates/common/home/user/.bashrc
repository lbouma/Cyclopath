# Retrosoft bash shell script

#no_trace=false
export DUBS_TRACE=false

# Source global definitions
if [[ -f "/etc/bashrc" ]]; then
  # Fedora
  . /etc/bashrc
elif [[ -f "/etc/bash.bashrc" ]]; then
  # Debian/Ubuntu
  . /etc/bash.bashrc
fi

# Source user scripts

$DUBS_TRACE && echo "User's EUID is $EUID"

if [[ $EUID -eq 0 ]]; then

  # If the user is root, just load the basic dubs script
  $DUBS_TRACE && echo "User is root"

  source  ./.bashrc-dub

else

  # Load the private script first so its exports are visible
  $DUBS_TRACE && echo "User is not root"

  # Rather than assuming we're in the user's home, e.g.,
  #  if [[ -f "./.bashrc_private" ]] ...
  # use the `echo` trick:
  if [[ -f `echo ~/.bashrc_private` ]]; then
    $DUBS_TRACE && echo "Loading private resource script: .bashrc_private"
    source ~/.bashrc_private
  fi

  # Load the machine-specific private script

  # FIXME Is there a difference between $(hostname) and $HOSTNAME?
  #       I know one is a command and one is an environment variable, 
  #       but does it matter which one I use?)
  ps=`echo ~/.bashrc_private.$HOSTNAME`

  $DUBS_TRACE && echo "Looking for machine-specific resource script: $ps"
  if [[ -f "$ps" ]]; then
    $DUBS_TRACE && echo "Loading machine-specific resource script: $ps"
    source $ps
  else
    ps=`echo ~/.bashrc_private.ccpv2`
    $DUBS_TRACE && echo "Loading generic machine resource script: $ps"
    source $ps
  fi

  ## Load all bash scripts that are named with a dash.
  #for f in $(find . -maxdepth 1 -type f -name ".bashrc-*")
  #  do
  #    #if [[ `echo ~/.bashrc_private` != $f ]]; then
  #      $DUBS_TRACE && echo "Loading Bash resource script: $f"
  #      source $f
  #    #fi
  #  done
  #
  # There are only two other bash scripts, and one should be loaded before the
  # other. So don't use a simple loop; use a smart loop!
  for f in ~/.bashrc-dub ~/.bashrc-cyclopath; do
    $DUBS_TRACE && echo "Loading Bash resource script: $f"
    source $f
  done

  # Start out in the Cyclopath development directory.
  # NOTE: When I do 'svn' from my laptop, this bash script is loading. (Which
  #       is probably because this should be a profile script, or whatever bash
  #       calls a startup script that is only loaded for interactive users.
  #       Though, above, we check for $EUID, so maybe I'm wrong about that.)
  #       Whatever, this works, too: just see if the directory exists.
  if [[ -n "$DUBS_STARTIN" ]]; then
    cd $DUBS_STARTIN
  elif [[ -d "$CCP_DEV_DIR" ]]; then
    cd $CCP_DEV_DIR
  fi
  # 2012.10.17: Added DUBS_STARTIN and DUBS_STARTUP.
  if [[ -n "$DUBS_STARTUP" ]]; then
    # Add the command we're about to execute to the command history (so if the
    # user Ctrl-C's the process, then can easily re-execute it).
    # See also: history -c, which clears the history.
    history -s $DUBS_STARTUP
    # Run the command.
    # FIXME: Does this hang the startup script? I.e., we're running the command
    #        from this script... so this better be the last command we run!
    $DUBS_STARTUP
  fi
  export DUBS_TERMNAME=''
  export DUBS_STARTUP=''
  export DUBS_STARTIN=''

fi

