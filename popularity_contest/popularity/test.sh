#!/bin/bash

curl -X POST -H "Content-Type: application/json"  -d '{"fog_version":"12.34.56","os_name":"Debian","os_version":"10"}' http://fog-popularity-contest.theworkmans.us:/api/records
