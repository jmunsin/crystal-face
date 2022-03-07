export PATH := $(PATH):$(shell cat ~/.Garmin/ConnectIQ/current-sdk.cfg)/bin

all:
	monkeyc -d fr245 -f monkey.jungle -o bin/crystal-face.prg -y ~/garmin/key/developer_key
	connectiq &
	monkeydo bin/crystal-face.prg fr245 &

compile:
	monkeyc -d fr245 -f monkey.jungle -o bin/crystal-face.prg -y ~/garmin/key/developer_key

fix:
	../fix.sh

