SHELL := /bin/bash

.EXPORT_ALL_VARIABLES:

KUBECONFIG = /tmp/mufg

.PHONY: all
all: /tmp/mufg

$(KUBECONFIG): creds.env
	@source creds.env; oc login -u "$$USER" -p "$$PASSWORD" "$$CLUSTER"
