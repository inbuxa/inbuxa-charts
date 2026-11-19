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

{{/*
K-C6: the mail listeners that get a PROXY copy, as INBUXA_MAIL_PROXY_LISTENERS
takes them ("smtp=10025,imaps=10993"): those the pods listen on and the mail
Service sends to. Empty when PROXY protocol is off.
*/}}
{{- define "inbuxa.server.proxyListeners" -}}
{{- $mail := .Values.server.services.mail -}}
{{- $items := list -}}
{{- if and $mail.enabled $mail.proxyProtocol.enabled -}}
{{- range $name := list "smtp" "submissions" "imaps" "pop3s" "sieve" -}}
{{- $target := int (index $.Values.server.listeners $name) -}}
{{- $port := int (index $mail.ports $name) -}}
{{- $proxy := int (index $mail.proxyProtocol.ports $name) -}}
{{- if and $target $port $proxy -}}
{{- $items = append $items (printf "%s=%d" $name $proxy) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- join "," $items -}}
{{- end -}}

{{/*
A front end's image, by digest when one is set. Its tag has no default: the
webmail and the console are versioned apart from the server. Call with
(dict "image" .Values.webmail.image "name" "webmail").
*/}}
{{- define "inbuxa.frontEnd.image" -}}
{{- $img := .image -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $img.repository $img.digest -}}
{{- else if $img.tag -}}
{{- printf "%s:%s" $img.repository $img.tag -}}
{{- else -}}
{{- fail (printf "%s.image.tag: set the %s release to run (27.1-rc.N); it's versioned apart from the server" .name .name) -}}
{{- end -}}
{{- end -}}

{{/* The host name of an https://host[:port] address. */}}
{{- define "inbuxa.hostOf" -}}
{{- (urlParse .).hostname | default (regexReplaceAll ":[0-9]+$" (urlParse .).host "") -}}
{{- end -}}

{{/*
Checks a front end's publicUrl: required, and https://host with no path.
Call with (dict "url" .Values.webmail.publicUrl "name" "webmail").
*/}}
{{- define "inbuxa.frontEnd.checkUrl" -}}
{{- if not .url -}}
{{- fail (printf "%s.publicUrl: set where browsers reach the %s, as https://host" .name .name) -}}
{{- end -}}
{{- if not (regexMatch "^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$" .url) -}}
{{- fail (printf "%s.publicUrl: %q should be https://host, with no path" .name .url) -}}
{{- end -}}
{{- end -}}

{{/* The server's egress rules (and the Jobs'): anywhere, or DNS plus networkPolicy.serverEgress. */}}
{{- define "inbuxa.networkPolicy.serverEgress" -}}
{{- if .Values.networkPolicy.serverEgress -}}
{{ include "inbuxa.networkPolicy.dns" . }}
{{ toYaml .Values.networkPolicy.serverEgress }}
{{- else -}}
# A mail server delivers to, and looks up, anywhere on the internet
- {}
{{- end -}}
{{- end -}}

{{/* DNS, to whichever resolver the cluster uses. */}}
{{- define "inbuxa.networkPolicy.dns" -}}
- ports:
    - {port: 53, protocol: UDP}
    - {port: 53, protocol: TCP}
{{- end -}}

{{/* The webmail's and the console's 8080: from networkPolicy.httpFrom, or anywhere. */}}
{{- define "inbuxa.networkPolicy.frontEndIngress" -}}
- ports:
    - {port: 8080, protocol: TCP}
  {{- with .Values.networkPolicy.httpFrom }}
  from:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
The TLS Secrets mounted in the server pods, space-separated: the ones named
in server.certificates.secrets, and the one cert-manager issues for the
chart.
*/}}
{{- define "inbuxa.server.tlsSecrets" -}}
{{- $c := .Values.server.certificates }}
{{- $names := $c.secrets }}
{{- if $c.certManager.enabled }}
{{- $names = append $names (printf "%s-mail-tls" (include "inbuxa.fullname" .)) }}
{{- end }}
{{- join " " (uniq $names) }}
{{- end }}

{{/* INBUXA_TLS_CERTIFICATE_DIRS for a list of TLS Secret names */}}
{{- define "inbuxa.server.tlsDirs" -}}
{{- $dirs := list }}
{{- range . }}
{{- $dirs = append $dirs (printf "/etc/inbuxa/tls/%s" .) }}
{{- end }}
{{- join "," $dirs }}
{{- end }}

{{/* The Secret with the metrics scrape username and password. */}}
{{- define "inbuxa.server.metricsSecret" -}}
{{- default (printf "%s-metrics" (include "inbuxa.fullname" .)) .Values.server.metrics.prometheus.existingSecret -}}
{{- end -}}
