#!/bin/bash

wait_for_es_to_up() {
  while [[ -z "$(curl -s localhost:9200)" ]]; do
    sleep 5
  done
}

create_index_metrics() {
  curl -s --header "Content-Type:application/json" -XPUT localhost:9200/metrics -d '{
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
  curl -s --header "Content-Type:application/json" -XPUT localhost:9200/workflow -d '{
    "settings": {
      "index.mapping.total_fields.limit": 5000
    },
    "mappings": {
      "properties": {
        "start_date": {
          "type": "date",
          "format": "yyyy-MM-dd HH:mm:ss"
        },
        "end_date": {
          "type": "date",
          "format": "yyyy-MM-dd HH:mm:ss"
        }
      }
    }
  }'
}

create_index() {
  echo "Creating ElasticSearch indexes.."
  wait_for_es_to_up
  create_index_metrics
  create_index_workflow
}

create_index
