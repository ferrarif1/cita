#!/bin/bash

set -e -o pipefail

display_help()
{
    echo
    echo "usage: $0 -a admin_id -l ip_list -n consensus_name -m crypto_method -t"
    echo "option:"
    echo "-a admin_id    admin identifier"
    echo "    default value is 'admin'"
    echo
    echo "-l ip_list     list all the node's IP and port"
    echo "    default value is '127.0.0.1:4000,127.0.0.1:4001,127.0.0.1:4002,127.0.0.1:4003'"
    echo
    echo "-n consensus_name  name of consensus algorithm"
    echo "    default value is 'cita-bft', other is 'raft' and 'poa'"
    echo
    echo "-m crypto_method    name of crypto algorithm"
    echo "    default value is 'SECP'"
    echo
    echo "-h enable jsonrpc http"
    echo "   default enable 'true'"
    echo
    echo "-w enable jsonrpc websocket "
    echo "   default enable 'true'"
    echo
    echo "-H define jsonrpc HTTP port"
    echo "   default port is '1337'"
    echo
    echo "-W define jsonrpc websocket port"
    echo "   default port is '4337'"
    echo
    echo "-k start with kafka"
    echo
    echo "-K define kafka port"
    echo "   default port is '9092'"
    echo
    echo "-G define grpc port"
    echo "   default port is '5000'"
    echo
    echo "-Q node id, use to create a new node, usually use with -l, -l must list all node ip"
    echo
    echo "-T timestamp of genesis"
    echo "   default value is current timestamp"
    echo
    echo "-C chain_id of current network"
    echo "   default value is random.randint(0, 2**29)"
    echo
    echo "-E economical model (enum: quota, charge)"
    echo "   default value is 'quota'"
    echo
    echo "-A authorities file of current network"
    echo "   default generated by create_key_addr for n nodes"
    echo
    echo "-i current chain id for chain management, a unique id"
    echo
    echo "-p parent chain id, the unique id of the parent chain"
    echo
    echo "-P parent chain nodes, the parent chain's consensus nodes"
    echo
    echo "-f prefix of node directories"
    echo
    echo "-D development mode, the port for HTTP, WebSocket, Kafka, GRPC ports will be increased automatically for nodes."
    echo "   default port is 'true'"
    echo
    echo "-S specify a step if do not want generate all files in one step."
    echo "   options: init-key | init-config."
    echo
    exit 0
}

# usually is `cita/targte/install`
CONFIG_DIR=${PWD}
# usually is `cita/targte/install`
if [[ `uname` == 'Darwin' ]]
then
    BINARY_DIR=$(realpath $(dirname $(realpath $0))/../..)
else
    BINARY_DIR=$(readlink -f $(dirname $(realpath $0))/../..)
fi

CONTRACTS_DOCS_DIR="${BINARY_DIR}/scripts/contracts/docs"
TEMPLATE_DIR="${BINARY_DIR}/scripts/admintool"
BACKUP_DIR="${CONFIG_DIR}/backup"
export PATH=${PATH}:${BINARY_DIR}/bin

# set default value
ADMIN_ID="admin"
IP_LIST="127.0.0.1:4000,127.0.0.1:4001,127.0.0.1:4002,127.0.0.1:4003"
DEVELOP_MODE=true
CONSENSUS_NAME="cita-bft"
CRYPTO_METHOD="SECP"
HTTP_ENABLE=true
WS_ENABLE=true
HTTP_PORT=1337
WS_PORT=4337
GRPC_PORT=5000
TIMESTAMP=0
CHAIN_ID=0
ECONOMICAL_MODEL="quota"
AUTHORITIES_FILE=
NODEDIR_PREFIX="node"
STEP=

# Parse options
while getopts 'a:l:n:m:h:w:g:H:W:G:Q:k:K:T:C:E:A:i:p:P:f:D:S:' OPT; do
    case $OPT in
        a)
            ADMIN_ID="$OPTARG";;
        l)
            IP_LIST="$OPTARG";;
        n)
            CONSENSUS_NAME="$OPTARG";;
        m)
            CRYPTO_METHOD="$OPTARG";;
        k)
            START_KAFKA=true;;
        K)
            KAFKA_PORT="$OPTARG";;
        h)
            HTTP_ENABLE="$OPTARG";;
        w)
            WS_ENABLE="$OPTARG";;
        H)
            HTTP_PORT="$OPTARG";;
        W)
            WS_PORT="$OPTARG";;
        G)
            GRPC_PORT="$OPTARG";;
        Q)
            NODE="$OPTARG";;
        T)
            TIMESTAMP="$OPTARG";;
        C)
            CHAIN_ID="$OPTARG";;
        E)
            ECONOMICAL_MODEL="$OPTARG";;
        A)
            AUTHORITIES_FILE="$OPTARG";;
        i)
            CURRENT_CHAIN_ID="$OPTARG";;
        p)
            PARENT_CHAIN_ID="$OPTARG";;
        P)
            PARENT_CHAIN_NODES="$OPTARG";;
        f)
            NODEDIR_PREFIX="$OPTARG";;
        D)
            DEVELOP_MODE="$OPTARG";;
        S)
            STEP="$OPTARG"
            if [ -n "${STEP}" ] \
                    && [ "${STEP}" != "init-key" ] \
                    && [ "${STEP}" != "init-config" ]; then
                display_help
            fi
            ;;
        ?)
            display_help
    esac
done

# Calc number of nodes
SIZE=$(echo "${IP_LIST}"| tr -s "," "\n" | grep ":" | wc -l)

TARGET_BAKDIR="${BACKUP_DIR}/${NODEDIR_PREFIX}"
TARGET_PUBDIR="${CONFIG_DIR}/${NODEDIR_PREFIX}"
GENESIS_FILE="${TARGET_PUBDIR}/genesis.json"
CHAIN_ID_FILE="${TARGET_PUBDIR}/chain_id"
AUTH_FILE="${TARGET_PUBDIR}/authorities"
RES_DIR="${TARGET_PUBDIR}/resource"

# Replace the default consensus in scripts
if [ "${CONSENSUS_NAME}" != "cita-bft" ]; then
    sed -i "s/cita-bft/${CONSENSUS_NAME}/g" "${BINARY_DIR}/bin/cita"
fi

function target_dir () {
    local nodeid=${1}
    printf "${CONFIG_DIR}/${NODEDIR_PREFIX}${nodeid}"
}

function create_genesis () {
    local init_data_json="${TARGET_PUBDIR}/init_data.json"
    if [ ! -e "${TEMPLATE_DIR}/init_data.json" ]; then
        cp "${TEMPLATE_DIR}/init_data_example.json" "${init_data_json}"
    else
        cp "${TEMPLATE_DIR}/init_data.json"         "${init_data_json}"
    fi

    cp -rf "${CONFIG_DIR}/resource" "${RES_DIR}"
    local args=
    if [ -n "${CURRENT_CHAIN_ID}" ]; then
        args="${args} --current_chain_id ${CURRENT_CHAIN_ID}"
    fi
    if [ -n "${PARENT_CHAIN_ID}" ] && [ -n "${PARENT_CHAIN_NODES}" ]; then
        args="${args} --parent_chain_id ${PARENT_CHAIN_ID}"
        args="${args} --parent_chain_nodes ${PARENT_CHAIN_NODES}"
    fi
    if [ -n "${AUTHORITIES_FILE}" ] && [ -f "${AUTHORITIES_FILE}" ]; then
        mv "${AUTH_FILE}" "${AUTH_FILE}.bak"
        cp -f "${AUTHORITIES_FILE}" "${AUTH_FILE}"
    fi
    python "${TEMPLATE_DIR}/create_genesis.py" \
        --timestamp ${TIMESTAMP} \
        --chain_id ${CHAIN_ID} \
        --economical_model ${ECONOMICAL_MODEL} \
        --genesis_file "${GENESIS_FILE}" \
        --chain_id_file "${CHAIN_ID_FILE}" \
        --authorities "${AUTH_FILE}" \
        --init_data "${init_data_json}" \
        --resource "${RES_DIR}/" \
        --permission "${TEMPLATE_DIR}/permission_init.json" \
        ${args}
    rm -f ${init_data_json}

    if [ ! -d "${CONTRACTS_DOCS_DIR}" ]; then
        mkdir -p "${CONTRACTS_DOCS_DIR}"
    fi
    mv *-userdoc.json *-devdoc.json *-hashes.json \
        ${CONTRACTS_DOCS_DIR}/
}

function create_key () {
    local nodeid=${1}
    python "${TEMPLATE_DIR}/create_keys_addr.py" \
        "$(target_dir ${nodeid})/" "${AUTH_FILE}" "create_key_addr"
}

function consensus () {
    local nodeid=${1}
    #python "${TEMPLATE_DIR}/create_node_config.py" \
    #    "$(target_dir ${nodeid})/"

    cp -f "${TEMPLATE_DIR}/consensus_config_example.toml" "$(target_dir ${nodeid})/consensus.toml"
}

# rabbitmq and kafka
function env () {
    local nodeid=${1}
    local envfile="$(target_dir ${nodeid})/.env"
    local kafka_port=$((KAFKA_PORT + nodeid))
    rm -rf ${envfile}
    echo "KAFKA_URL=localhost:${kafka_port}"                                >> ${envfile}
    echo "AMQP_URL=amqp://guest:guest@localhost/${NODEDIR_PREFIX}${nodeid}" >> ${envfile}
    echo "DATA_PATH=./data"                                                 >> ${envfile}
}

function auth () {
    local nodeid=${1}
    cp -f "${TEMPLATE_DIR}/auth_example.toml" "$(target_dir ${nodeid})/auth.toml"
}

function network () {
    local nodeid=${1}
    local append_mode=${2}
    if [ "${append_mode}" = "true" ]; then
        for ((ID=0;ID<$SIZE;ID++)); do
            local update_existed=true
            if [ "${ID}" = "${nodeid}" ]; then
                update_existed=false
            fi
            python "${TEMPLATE_DIR}/create_network_config.py" \
                "$(target_dir ${ID})/network.toml" \
                ${nodeid} \
                $IP_LIST \
                ${update_existed}
        done
    else
        local update_existed=false
        python "${TEMPLATE_DIR}/create_network_config.py" \
            "$(target_dir ${nodeid})/network.toml" \
            ${nodeid} \
            $IP_LIST \
            ${update_existed}
    fi
}


function chain () {
    local nodeid=${1}
    if [ -d "${RES_DIR}" ]; then
        cp -rf "${RES_DIR}" "$(target_dir ${nodeid})/"
    fi
    cp -f "${TEMPLATE_DIR}/chain_config_example.toml" "$(target_dir ${nodeid})/chain.toml"
}

function executor () {
    local nodeid=${1}
    local append_mode=${2}
    cp "${GENESIS_FILE}" "$(target_dir ${nodeid})/"
    cp "${CHAIN_ID_FILE}" "$(target_dir ${nodeid})/"
    if [ -d "${RES_DIR}" ]; then
        cp -rf "${RES_DIR}" "$(target_dir ${nodeid})/"
    fi

    local grpc_port=${GRPC_PORT}
    if [ "${DEVELOP_MODE}" == "true" ] || [ "${append_mode}" == "true" ]; then
        grpc_port=$((grpc_port + nodeid))
    fi
    python "${TEMPLATE_DIR}/create_executor_config.py" \
        "$(target_dir ${nodeid})/executor.toml" ${grpc_port}

}

function jsonrpc () {
    local nodeid=${1}
    local append_mode=${2}
    local http_port=${HTTP_PORT}
    local ws_port=${WS_PORT}
    if [ "${DEVELOP_MODE}" == "true" ] || [ "${append_mode}" == "true" ]; then
        http_port=$((http_port + nodeid))
        ws_port=$((ws_port + nodeid))
    fi
    python "${TEMPLATE_DIR}/create_jsonrpc_config.py" \
        ${HTTP_ENABLE}  ${http_port} \
        ${WS_ENABLE}    ${ws_port} \
        "$(target_dir ${nodeid})/"
}

# Kafka Configuration creating
function kafka () {
    local nodeid=${1}
    if [ "$START_KAFKA" == "true" ];then
        "${TEMPLATE_DIR}/create_kafka_config.sh"     ${nodeid} "$(target_dir ${nodeid})/"
        "${TEMPLATE_DIR}/create_zookeeper_config.sh" ${nodeid} "$(target_dir ${nodeid})/"
    fi
}

function forever () {
    local nodeid=${1}
    cp -f "${TEMPLATE_DIR}/forever_example.toml" "$(target_dir ${nodeid})/forever.toml"
}

function backup_files () {
    if [ ! -d "${BACKUP_DIR}" ]; then
        mkdir -p "${BACKUP_DIR}"
    fi
    if [ -d "${TARGET_BAKDIR}" ]; then
        rm -rf "${TARGET_BAKDIR}"
    fi
    mv "${TARGET_PUBDIR}" "${TARGET_BAKDIR}"
}

function restore_backup_files () {
    cp -rf "${TARGET_BAKDIR}" "${TARGET_PUBDIR}"
}

function node_init_key () {
    local nodeid=${1}
    local nodedir="$(target_dir ${nodeid})"
    # Create new node directory
    if [ -d "${nodedir}" ]; then
        rm -rf "${nodedir}"
    fi
    mkdir -p "${nodedir}"
    create_key ${nodeid}
}

function node_init_configs () {
    local nodeid=${1}
    local append_mode=${2}
    jsonrpc ${nodeid} ${append_mode}
    consensus ${nodeid}
    chain ${nodeid}
    executor ${nodeid} ${append_mode}
    network ${nodeid} ${append_mode}
    auth ${nodeid}
    env ${nodeid}
    kafka ${nodeid}
    forever ${nodeid}
}

# Append new node, not initialize the entire chain
function node_append () {
    local nodeid=${1}
    if [ -z "${STEP}" ] || [ "${STEP}" = "init-key" ]; then
        restore_backup_files
        node_init_key ${nodeid}
    fi
    if [ -z "${STEP}" ] || [ "${STEP}" = "init-config" ]; then
        node_init_configs ${nodeid} true
        backup_files
    fi
}

function nodes_create () {
    if [ -z "${STEP}" ] || [ "${STEP}" = "init-key" ]; then
        if [ -d "${TARGET_PUBDIR}" ]; then
            rm -rf "${TARGET_PUBDIR}"
        fi
        mkdir -p "${TARGET_PUBDIR}"
        for ((ID=0;ID<$SIZE;ID++)); do
            node_init_key ${ID}
        done
    fi
    if [ -z "${STEP}" ] || [ "${STEP}" = "init-config" ]; then
        create_genesis
        for ((ID=0;ID<$SIZE;ID++)); do
            node_init_configs ${ID}
        done
        backup_files
    fi
}

echo "************************begin create node config******************************"
if [ -z $NODE ]; then
    # initialize the entire chain
    nodes_create
else
    # append new node
    node_append $NODE
fi
echo "************************end create node config********************************"
echo "WARN: remember then delete all privkey files!!!"
