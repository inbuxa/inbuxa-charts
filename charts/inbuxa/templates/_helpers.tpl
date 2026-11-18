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
