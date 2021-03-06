#!/usr/bin/env bash
# -x

#__main()__________

# Source Nutanix environment (PATH + aliases), then common routines + global variables
. /etc/profile.d/nutanix_env.sh
. lib.common.sh
. global.vars.sh
begin

args_required 'EMAIL PE_PASSWORD PC_VERSION PC_HOST AUTH_HOST SNOWInstanceURL'

#dependencies 'install' 'jq' && ntnx_download 'PC' & #attempt at parallelization
# Some parallelization possible to critical path; not much: would require pre-requestite checks to work!

case ${1} in
  PE | pe )
    . lib.pe.sh
    . lib.pe.api.sh

    export AUTH_SERVER='AutoAD'
    export STORAGE_ERA='SelfServiceContainer'
    # Networking needs for Era Bootcamp
	  #export NW2_NAME='EraManaged'
    export NW1_SUBNET="${IPV4_PREFIX}.0"
    export NW1_DHCP_START="${IPV4_PREFIX}.45"
    export NW1_DHCP_END="${IPV4_PREFIX}.110"
    export NW2_SUBNET="${IPV4_PREFIX}.128"
    export NW2_DHCP_START="${IPV4_PREFIX}.132"
    export NW2_DHCP_END="${IPV4_PREFIX}.210"
    export NW3_START="${IPV4_PREFIX}.211"
    export NW3_END="${IPV4_PREFIX}.253"

    args_required 'PE_HOST PC_LAUNCH'
    ssh_pubkey & # non-blocking, parallel suitable

    dependencies 'install' 'sshpass' && dependencies 'install' 'jq' \
    && pe_license_api \
    && pe_init_api \
    && era_network_configure_api \
    && authentication_source \
    && pe_auth_api \
    && prism_pro_server_deploy \
    && deploy_windows_tools_vm \
    && deploy_api_citrix_gold_image_vm

    if (( $? == 0 )) ; then
      pc_install "${NW1_NAME}" \
      && prism_check 'PC' \

      if (( $? == 0 )) ; then
        _command="EMAIL=${EMAIL} \
           PC_HOST=${PC_HOST} PE_HOST=${PE_HOST} PE_PASSWORD=${PE_PASSWORD} \
           PC_LAUNCH=${PC_LAUNCH} PC_VERSION=${PC_VERSION} nohup bash ${HOME}/${PC_LAUNCH} IMAGES"

        cluster_check \
        && log "Remote asynchroneous PC Image import script... ${_command}" \
        && remote_exec 'ssh' 'PC' "${_command} >> ${HOME}/${PC_LAUNCH%%.sh}.log 2>&1 &" &

        pc_configure \
        && log "PC Configuration complete: Waiting for PC deployment to complete, API is up!"
        log "PE = https://${PE_HOST}:9440"
        log "PC = https://${PC_HOST}:9440"


        #&& dependencies 'remove' 'jq' & # parallel, optional. Versus: $0 'files' &
        #dependencies 'remove' 'sshpass'
        finish
      fi
    else
      finish
      _error=18
      log "Error ${_error}: in main functional chain, exit!"
      exit ${_error}
    fi
  ;;
  PC | pc )
    . lib.pc.sh

    export _prio_images_arr=(\
      CentOS7.qcow2 \
      Windows2016.qcow2 \
      Citrix_Virtual_Apps_and_Desktops_7_1912.iso \
      MSSQL16-Source-Disk1.qcow2 \
      MSSQL16-Source-Disk2.qcow2 \
    )

    export QCOW2_IMAGES=(\
    )
    export ISO_IMAGES=(\
      Nutanix-VirtIO-1.1.5.iso \
    )

    run_once

    dependencies 'install' 'jq' || exit 13

    ssh_pubkey & # non-blocking, parallel suitable

    pc_passwd
    ntnx_cmd # check cli services available?

    export   NUCLEI_SERVER='localhost'
    export NUCLEI_USERNAME="${PRISM_ADMIN}"
    export NUCLEI_PASSWORD="${PE_PASSWORD}"
    # nuclei -debug -username admin -server localhost -password x vm.list

    if [[ -z "${PE_HOST}" ]]; then # -z ${CLUSTER_NAME} || #TOFIX
      log "CLUSTER_NAME=|${CLUSTER_NAME}|, PE_HOST=|${PE_HOST}|"
      pe_determine ${1}
      . global.vars.sh # re-populate PE_HOST dependencies
    else
      CLUSTER_NAME=$(ncli --json=true multicluster get-cluster-state | \
                      jq -r .data[0].clusterDetails.clusterName)
      if [[ ${CLUSTER_NAME} != '' ]]; then
        log "INFO: ncli multicluster get-cluster-state looks good for ${CLUSTER_NAME}."
      fi
    fi

    export ATTEMPTS=2
    export    SLEEP=10

    pc_init \
    && pc_dns_add \
    && pc_ui \
    && pc_auth \
    && pc_smtp

    ssp_auth \
    && calm_enable \
    && objects_enable \
    && karbon_enable \
    && lcm \
    && pc_project \
    && object_store \
    && karbon_image_download \
    && priority_images \
    && flow_enable \
    && pc_cluster_img_import \
    && create_categories \
    && upload_citrix_calm_blueprint \
    && upload_snow_calm_blueprint \
    && upload_fiesta_mssql_blueprint \
    && images \
    && prism_check 'PC'

    log "Non-blocking functions (in development) follow."
    #pc_project
    pc_admin
    # ntnx_download 'AOS' # function in lib.common.sh

    unset NUCLEI_SERVER NUCLEI_USERNAME NUCLEI_PASSWORD

    if (( $? == 0 )); then
      #dependencies 'remove' 'sshpass' && dependencies 'remove' 'jq' \
      #&&
      log "PC = https://${PC_HOST}:9440"
      finish
    else
      _error=19
      log "Error ${_error}: failed to reach PC!"
      exit ${_error}
    fi
  ;;
esac
