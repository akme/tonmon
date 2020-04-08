#!/usr/bin/env bash
set -uo pipefail

LITECONFIG="/path/to/ton-lite-client-test1.config.json"
LITECLIENTBIN="/path/to/lite-client"
METRICSFILE="file2"
PREFIX="ton"

check_files_exists()
{
    if [ $# -ge 1 ]; then
        local files=("$@")
        for file in "${files[@]:0:${#files[@]}}"; do
			if [ ! -f "$file" ]; then
		        echo "File not found: $file"
	        fi
		done
    else
        echo "no files provided for checking"
    fi
}

check_files_exists ${LITECONFIG}

check_installed() {
	EXIT=0
	for cmd in "grep" "awk" "sed" "bc" ${LITECLIENTBIN}; do
		if ! [ -x "$(command -v $cmd)" ]; then
			echo "Error: $cmd is not installed." >&2
			EXIT=1
		fi
	done
	if [ "$EXIT" -eq 1 ]; then
		exit 1
	fi
}

check_installed

do_cmd()
{
    OUTPUT=$("$@")
    ret=$?
    if [[ $ret -eq 0 ]]
    then
        echo -n "${OUTPUT}"
    else
        echo "Error: Command [" "$@" "] returned $ret"
        exit $ret
    fi
}

run_lite_cmd()
{
    do_cmd ${LITECLIENTBIN} -C ${LITECONFIG} -t 30 -v 0 -c "$1"
}

metric_name()
{
    if [ $# == 1 ]; then
        echo "${PREFIX}_$1"
    fi
}

print_metric() # metric_name type desc result
{
    if [ $# == 4 ]; then
        local metric metric_type description result
        metric=$(metric_name "$1")
        metric_type="$2"
        description="$3"
        result="$4"
        echo "# HELP ${metric} ${description}"
        echo "# TYPE ${metric} ${metric_type}"
        echo "${metric} ${result}"
    fi
}

get_elections_address()
{
    local result
    result=$(run_lite_cmd "getconfig 1"|grep x{|sed -e 's/{/\ /g' -e 's/}//g'|awk {'print $2'})
    echo "-1:${result}"
}

ACTIVE_ELECTION_ID=$(get_elections_address)


logdate() {
	date '+%s (%Y-%m-%d %H:%M:%S)'
}

get_mc_last_block()
{
    local metric result
    metric="mc_last_block"
    result=$(run_lite_cmd "last"|grep latest|head -n 1|awk {'print $8'}|tr ',' ' '|tr '\)' ' '|awk {'print $3'})
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Masterchain block height" "$result"
    fi
}

get_cur_validators()
{
    local metric result
    metric="cur_validators"
    result=$(run_lite_cmd "getconfig 34"|grep cur_val|awk {'print $4'}| tr \: " "|awk {'print $2'})
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Current number of validators" "$result"
    fi
}

get_cur_validators_weight()
{
    local metric description metric_type
    description="Validators weight"
    metric_type="gauge"
    metric="cur_validators_weight"
    metric=$(metric_name "$metric")
    echo "# HELP ${metric} ${description}"
    echo "# TYPE ${metric} ${metric_type}"
    while read -r line
    do 
        local pub_key weight
        read -r pub_key weight <<< "$(echo "$line"|awk '{print $1" "$2}')"
        echo  "${metric}{public_key=\"$pub_key\"} ${weight}"
    done < <(run_lite_cmd "getconfig 34"|grep public_key|tr ':' ' '|sed -e 's/x//g' -e 's/)//g'|awk '{print $4" "$6}')

}

get_elections_state()
{
    local metric result
    metric="elections_state"
    result=$(run_lite_cmd "runmethod ${ACTIVE_ELECTION_ID} active_election_id"|grep result\:|awk {'if($3=="0"){print "0"} else {print "1"}'})
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Elections state" "$result"
    fi
}

get_elections_stakes()
{
    local metric result
    metric="elections_stakes"
    result=$(run_lite_cmd "runmethod ${ACTIVE_ELECTION_ID} participant_list"|grep result|sed -e 's/(\[//g' -e 's/\] \[/\n/g' -e '0,/\]/{s/\]/\n/}' -e 's/\[/\n/g'|grep -v \]|grep -v result|awk '{sum += $2} END {print sum/1000000000}')
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Amount of stakes for current elections" "$result"
    fi
}

get_elections_participants()
{
    local metric result
    metric="elections_participants"
    result=$(run_lite_cmd "runmethod ${ACTIVE_ELECTION_ID} participant_list"|grep result|sed -e 's/(\[//g' -e 's/\] \[/\n/g' -e '0,/\]/{s/\]/\n/}' -e 's/\[/\n/g'|grep -v '\]'|grep -v result|grep -v \(\)|grep "\S"|awk 'END{print NR}')
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Number of participants in elections" "$result"
    fi
}

get_elections_participants_stakes()
{
    local metric description metric_type
    description="Participants stakes"
    metric_type="gauge"
    metric="elections_participants_stakes"
    metric=$(metric_name "$metric")
    echo "# HELP ${metric} ${description}"
    echo "# TYPE ${metric} ${metric_type}"
    while read -r line
    do 
        local pub_key value
        read -r pub_key value <<< "$(echo "$line"|awk '{print $1" "$2/1000000000}')"
        if [ "$pub_key" != 0 ]; then
            echo -n "${metric}"
            echo "{public_key=\"$(echo "obase=16; $pub_key"|bc)\"} ${value}"
        fi
    done < <(run_lite_cmd "runmethod ${ACTIVE_ELECTION_ID} participant_list" 2> >(cat)|grep result|sed -e 's/(\[//g' -e 's/\] \[/\n/g' -e '0,/\]/{s/\]/\n/}' -e 's/\[/\n/g'|grep -v \]|grep -v result|grep -v \(\))
}

get_elections_contract_balance()
{
    local metric result
    metric="elections_contract_balance"
    result=$(run_lite_cmd "getaccount ${ACTIVE_ELECTION_ID}"|grep balance|tail -n 1|awk {'print $4'}|rev|cut -c 3-|rev)
    result=$((${result} / 1000000000))
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Amount of GRAMS staked" "$result"
    fi
}

get_transactions_counter()
{
    local metric result
    metric="transactions"
    result=$(cat /tmp/trans/transactions)
    print_metric "${metric}" counter "Transactions counter" "$result"
}

get_nodes()
{
#    find . -maxdepth 1 -mmin +1 -type f -exec sh -c "tcpdump -nnn -t -r {} | cut -f 1,2,3,4 -d '.' | sort | uniq -c | sort -nr|wc -l; rm {}" \; -print
echo "TODO"
}

get_shards_info()
{
    local metric result
    metric="shards_number"
    result=$(run_lite_cmd "allshards"|grep 'shard #'|sed -e 's/,/ /g' -e 's/)/ /g' -e 's/\#//g'|awk 'END {print NR}')
    if [ $? -eq 0 ]; then
        print_metric "${metric}" gauge "Number of shards" "$result"
    fi
}

get_allshards()
{
    local metric description metric_type
    description="All shards block height"
    metric_type="gauge"
    metric="allshards"
    metric=$(metric_name "$metric")
    echo "# HELP ${metric} ${description}"
    echo "# TYPE ${metric} ${metric_type}"
    while read -r line
    do 
        local shard_num shard_height
        read -r shard_num shard_height <<< "$(echo "$line"|awk '{print $1" "$2}')"
        echo  "${metric}{shard_num=\"$shard_num\"} ${shard_height}"
    done < <(run_lite_cmd "allshards"|grep "shard #"|sed -e 's/#//g' -e 's/,/ /g' -e 's/)/ /g'|awk '{print $2" "$6}')
}

get_creator_stats()
{
    local result
    last_block=$(run_lite_cmd "last"|grep latest|awk '{print $8}'|head -n1)
    result=$(run_lite_cmd "creatorstats $last_block"|grep 0000000000000000000000000000000000000000000000000000000000000000|tr ':' ' '|tr ')' ' '|awk '{print $7" " $9" "$11" "$17" "$19" "$21}')
    read -r creatorstats_mc_total creatorstats_mc_cnt2048 creatorstats_mc_cnt65536 creatorstats_shard_total creatorstats_shard_cnt2048 creatorstats_shard_cnt65536 <<< $(echo "$result")
    print_metric "creatorstats_mc_total" gauge "Total creatorstats for masterchain" "$creatorstats_mc_total"
    print_metric "creatorstats_mc_cnt2048" gauge "cnt2048 creatorstats for masterchain" "$creatorstats_mc_cnt2048"
    print_metric "creatorstats_mc_cnt65536" gauge "cnt65536 creatorstats for masterchain" "$creatorstats_mc_cnt65536"
    print_metric "creatorstats_shard_total" gauge "Total creatorstats for shardchains" "$creatorstats_shard_total"
    print_metric "creatorstats_shard_cnt2048" gauge "cnt2048 creatorstats for shardchains" "$creatorstats_shard_cnt2048"
    print_metric "creatorstats_shard_cnt65536" gauge "cnt65536 creatorstats for shardchains" "$creatorstats_shard_cnt65536"
}

print_metrics ()
{
    echo "# metrics file generated at $(logdate)" 
    get_cur_validators
    get_mc_last_block
    get_elections_stakes
    get_elections_state
    get_elections_participants
    get_elections_contract_balance
    get_creator_stats
    get_shards_info
    get_elections_participants_stakes
    get_cur_validators_weight
    get_allshards
    get_transactions_counter
}

save_metrics()
{
    print_metrics>${METRICSFILE}
}

save_metrics
