
# Route Analytics

# First, start routed.
# And make sure you uncomment the DEVHACK sections in route_analysis.py.

sudo -u apache \
  INSTANCE=minnesota \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  ./routedctl \
  --routed_pers=p1 \
  --purpose=analysis \
  start

sudo -u $httpd_user \
  INSTANCE=minnesota \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  /export/scratch/ccp/dev/cp/pyserver/ccp.py \
    -U landonb \
    --no-password \
    -c \
    -t route_analysis_job \
    -m "" \
    -b 0 \
    -e name Job8 \
    -e job_act create \
    -e n 1 \
    -e regions_ep_1 "Minneapolis" \
    -e job_local_run 1

sudo -u $httpd_user \
  INSTANCE=minnesota \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  /export/scratch/ccp/dev/cp/pyserver/ccp.py \
    -U landonb \
    --no-password \
    -c \
    -t route_analysis_job \
    -m "" \
    -b 0 \
    -e name Job8 \
    -e job_act create \
    -e n 1 \
    -e regions_ep_1 "Minneapolis" \
    -e regions_ep_2 "St. Paul" \
    -e job_local_run 1

sudo -u $httpd_user \
  INSTANCE=minnesota \
  PYTHONPATH=$PYTHONPATH \
  PYSERVER_HOME=$PYSERVER_HOME \
  /export/scratch/ccp/dev/cp/pyserver/ccp.py \
    -U landonb \
    --no-password \
    -c \
    -t route_analysis_job \
    -m "" \
    -b 0 \
    -e name Job8 \
    -e job_act create \
    -e n 1 \
    -e rider_profile 100pc_bikeability
    -e job_local_run 1

