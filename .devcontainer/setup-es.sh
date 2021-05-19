#!/bin/bash

wait_for_es_to_up() {
  while [[ -z "$(curl -s $ES_HOST:$ES_PORT)" ]]; do
    sleep 5
  done
}

create_index_metrics() {
  curl -s --header "Content-Type:application/json" -XPUT $ES_HOST:$ES_PORT/metrics -d '{
    "mappings": {
      "properties": {
        "timestamp": {
          "type": "date",
          "format": "epoch_second"
        }
      }
    }
  }'
}

create_index_workflow() {
  curl -s --header "Content-Type:application/json" -XPUT $ES_HOST:$ES_PORT/workflow -d '{
    "settings": {
      "index.mapping.total_fields.limit": 5000
    }
  }'
}

create_index() {
  echo 'Creating ElasticSearch indices..'
  wait_for_es_to_up
  
  msg=$(curl -s -XGET $ES_HOST:$ES_PORT/metrics | jq .metrics)
  if [ "$msg" = 'null' ]; then
    create_index_metrics
    create_index_workflow
  else
    echo 'Warning: Indices are already created.'
    echo '         ES container may store old workflow metrics.'
    echo '         If you want to initialize ES server, execute the following command:'
    echo '         curl -XDELETE $ES_HOST:$ES_PORT/* && /workspace/ep3/.devcontainer/setup-es.sh'
  fi
}

create_index
