{{/*
SPDX-FileCopyrightText: 2026 Coffey Labs LLC
SPDX-License-Identifier: Apache-2.0
*/}}

{{/* The chart's name, or nameOverride. */}}
{{- define "inbuxa.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{/*
The prefix of every object's name. Kept to 52 characters, so a suffix such
as "-front" or "-webmail" still fits the 63 a label value allows.
*/}}
{{- define "inbuxa.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 52 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "inbuxa.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 52 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 52 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart name and version, as the helm.sh/chart label wants them. */}}
{{- define "inbuxa.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels that select a component's pods. Never change across upgrades. */}}
{{- define "inbuxa.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inbuxa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Every object's labels. */}}
{{- define "inbuxa.labels" -}}
helm.sh/chart: {{ include "inbuxa.chart" . }}
{{ include "inbuxa.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: inbuxa
{{- end -}}

{{/* The server image, by digest when one is set. */}}
{{- define "inbuxa.server.image" -}}
{{- $img := .Values.server.image -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $img.repository $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $img.repository (default .Chart.AppVersion $img.tag) -}}
{{- end -}}
{{- end -}}

{{/* A server group's selector labels. Call with (dict "root" $ "group" "front"). */}}
{{- define "inbuxa.server.selectorLabels" -}}
{{ include "inbuxa.selectorLabels" .root }}
app.kubernetes.io/component: server
inbuxa.org/group: {{ .group }}
{{- end -}}

{{/* INBUXA_LISTENER_PORTS: name=port for each listener, off for a 0. */}}
{{- define "inbuxa.server.listenerPorts" -}}
{{- $items := list -}}
{{- range $name := list "smtp" "submissions" "imaps" "pop3s" "sieve" "https" "http" -}}
{{- $port := int (index $.Values.server.listeners $name) -}}
{{- $items = append $items (printf "%s=%s" $name (ternary "off" (toString $port) (eq $port 0))) -}}
{{- end -}}
{{- join "," $items -}}
{{- end -}}
