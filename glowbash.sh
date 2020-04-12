#!/bin/bash

# Authenticate against the glowmarkt API and return some data from the API

# Stuart Robertson, iDelta, April 2020 

# "All of the bash problems are quotes" 

AUTH_ENDPOINT="https://api.glowmarkt.com/api/v0-1/auth"
GET_RESOURCES_ENDPOINT="https://api.glowmarkt.com/api/v0-1/resource"
APPLICATION_ID=b0f1b774-a586-4f72-9edd-27ead8aa7a8d
TOKEN_SAVE_FILE=./.token_save
RESOURCES_SAVE_FILE=./.resources_save

# Script will test to see if the current token is valid or running out soon - this var control how soon - 86400 = 1 day
# => So reauthenticate if token expires in the next 24h
REAUTH_LIMIT=86400

function call_auth() {
	#returns jwt and expiry datetime as epoch into variables $1 and $2
	local __resultvar1=$1
	local __resultvar2=$2
	echo "Enter username:"
	read username
	echo "Enter password:"
	read -s password
	json_response="$(curl -X POST -H "Content-Type: application/json" -H "applicationId: ${APPLICATION_ID}" -d '{ "username":"'"${username}"'", "password":"'"${password}"'" }' ${AUTH_ENDPOINT} 2>/dev/null)"
	#check if the call worked
	if [ "${json_response}" = "{\"valid\":false}" ] || [ "${json_response}" = "{\"error\":\"An error has occurred\"}" ]
	then
		echo "Auth failed - JSON response was: ${json_response}" >> /dev/stderr

		#Auth failed - exit now
		exit 2
	else
		local __jwt=$(echo "$json_response" |sed -E 's/^.*token\"\:(.*),"exp.*/\1/')
		local __exp=$(echo "$json_response" |sed -E 's/^.*token\"\:.*,\"exp\"\:(.*),\"userGroups.*/\1/')
	fi
	eval $__resultvar1=$__jwt
	eval $__resultvar2=$__exp
}

function write_token() {
	local __token=$1
	local __expiry=$2
	echo "token=${__token}" > $TOKEN_SAVE_FILE
	echo "expiry=${__expiry}" >> $TOKEN_SAVE_FILE
}

function get_token() {
	local __resultvar1=$1
	#read the token and expiry stored on disk
	#check if the token save file exists:
	if [ -f ${TOKEN_SAVE_FILE} ]
	then
		. ${TOKEN_SAVE_FILE}
		local now_time=$(date +%s)
		local token_lifetime=$(expr $expiry - $now_time)
		if [ $token_lifetime -gt $REAUTH_LIMIT ]
		then
			# Use stored token
			local return_token=$token
		else
			# refresh the token
			call_auth return_token auth_expiry
			write_token $return_token $auth_expiry
		fi
	else
		#token save file does not exist
		call_auth return_token auth_expiry
                write_token $return_token $auth_expiry
	fi
	#return the token value into the variable specified on the function call
	eval $__resultvar1=$return_token
}

function checkResources() {
	#Check if the resources file exists - if not then create it
	local __checkResourcesToken=$1
	if [ ! -f ${RESOURCES_SAVE_FILE} ]
	then
		updateResourcesFile ${__checkResourcesToken}
	fi
}

function writeResources() {
	local __writeResourcesToken=$1
	local resources="$(curl -X GET -H "Content-Type: application/json" -H "token:${__writeResourcesToken}" -H "applicationId:${APPLICATION_ID}" ${GET_RESOURCES_ENDPOINT} 2>/dev/null)"
	echo $resources
}

function updateResourcesFile() {
	local __getResourcesToken=$1
	local resources=$(writeResources $__getResourcesToken)
	local gasConsumptionResourceId=$(echo $resources| sed -E 's/.*\"gas\.consumption\",\"baseUnit\":\"\kWh\",\"resourceId\"\:("[0-9a-z-]+\"),.*/\1/')
	local electricityConsumptionResourceId=$(echo $resources| sed -E 's/.*\"electricity\.consumption\",\"baseUnit\":\"\kWh\",\"resourceId\"\:("[0-9a-z-]+\"),.*/\1/')
	local gasConsumptionCostResourceId=$(echo $resources| sed -E 's/.*\"gas\.consumption\.cost\",\"baseUnit\":\"\pence\",\"resourceId\"\:("[0-9a-z-]+\"),.*/\1/')
        local electricityConsumptionCostResourceId=$(echo $resources| sed -E 's/.*\"electricity\.consumption\.cost\",\"baseUnit\":\"\pence\",\"resourceId\"\:("[0-9a-z-]+\"),.*/\1/')
	#write resource identifiers to save file
	echo "gasConsumption=${gasConsumptionResourceId}" > $RESOURCES_SAVE_FILE
	echo "electricityConsumption=${electricityConsumptionResourceId}" >> $RESOURCES_SAVE_FILE
	echo "gasConsumptionCost=${gasConsumptionCostResourceId}" >> $RESOURCES_SAVE_FILE
        echo "electricityConsumptionCost=${electricityConsumptionCostResourceId}" >> $RESOURCES_SAVE_FILE

}

function getCurrentElectricity() {
	local __getCurElecToken=$1
	local __elecLive=$(curl -X GET -H "Content-Type: application/json" -H "token: ${__getCurElecToken}" -H "applicationId: b0f1b774-a586-4f72-9edd-27ead8aa7a8d" "https://api.glowmarkt.com/api/v0-1/resource/${electricityConsumption}/current" 2>/dev/null | sed -E 's/^.*\[\[[0-9]+\,([0-9]+)\]\].*/\1/')
	echo $__elecLive

}

function getCurrentGas() {
	local __getCurGasToken=$1
	curl -X GET -H "Content-Type: application/json" -H "token: ${__getCurGasToken}" -H "applicationId: b0f1b774-a586-4f72-9edd-27ead8aa7a8d" "https://api.glowmarkt.com/api/v0-1/resource/${gasConsumption}/current" 2>/dev/null
}


function liveElecDisplay() {
	local __liveToken=$1
	while true
	do
		local elecReading=$(getCurrentElectricity $1)
		#Should change this to use the units specified in the API response
		local display="${elecReading} Watts"
		printf "%s%s\r" "electricity:" "$display"
		sleep 10
	done
}
##
#Main Program
##

#Authenticate
get_token jwt_token
#Get users resources
checkResources $jwt_token
#source the resources file
. ./${RESOURCES_SAVE_FILE}
#Live Display of Electricity Consumption
liveElecDisplay $jwt_token


