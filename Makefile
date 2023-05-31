SHELL := /bin/bash

.EXPORT_ALL_VARIABLES:

KUBECONFIG = /tmp/mufg

.PHONY: all
all: bootstrap

$(KUBECONFIG): creds.env
	@source creds.env; oc login -u "$$USER" -p "$$PASSWORD" "$$CLUSTER"

.PHONY: bootstrap
bootstrap: $(KUBECONFIG)
	oc apply -k bootstrap
