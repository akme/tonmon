#!/usr/bin/env bash

block_counter=$(cat blockid)
transactions=$(cat transactions)
while true
    do 
        block_counter=$(cat blockid)
        transactions=$(cat transactions)
        block=$(/path/to/lite-client/lite-client -C /home/wallet/ton-lite-client-test1.config.json -v 0 -c "last" 2> >(tail -n 1|awk {'print $8'}))
        if [ "$block_counter" != "$block" ]
        then
            trans_num=$(/path/to/lite-client/lite-client -C /home/wallet/ton-lite-client-test1.config.json -v 0 -c "listblocktrans $block 100" 2> >(tail -n 2| head -n 1|awk {'print $2'}|sed -e 's/#//g' -e 's/://g'))
            echo $(("$transactions"+"$trans_num")) > transactions
        fi
        sleep 3
done