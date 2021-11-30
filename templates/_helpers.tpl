{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "vcagent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "vcagent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vcagent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The name of the ServiceAccount used.
*/}}
{{- define "vcagent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "vcagent.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
The name of the PodSecurityPolicy used.
*/}}
{{- define "vcagent.podSecurityPolicyName" -}}
{{- if .Values.podSecurityPolicy.enable -}}
{{ default (include "vcagent.fullname" .) .Values.podSecurityPolicy.name }}
{{- end -}}
{{- end -}}

{{/*
Prints out the name of the secret to use to retrieve the agent key
*/}}
{{- define "vcagent.keysSecretName" -}}
{{- if .Values.agent.keysSecret -}}
{{ .Values.agent.keysSecret }}
{{- else -}}
{{ template "vcagent.fullname" . }}
{{- end -}}
{{- end -}}

{{/*
Add Helm metadata to resource labels.
*/}}
{{- define "vcagent.commonLabels" -}}
app.kubernetes.io/name: {{ include "vcagent.name" . }}
app.kubernetes.io/version: {{ .Chart.Version }}
{{- if not .Values.templating }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "vcagent.chart" . }}
{{- end -}}
{{- end -}}

{{/*
Add Helm metadata to selector labels specifically for deployments/daemonsets/statefulsets.
*/}}
{{- define "vcagent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vcagent.name" . }}
{{- if not .Values.templating }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- end -}}

{{/*
Generates the dockerconfig for the credentials to pull from containers.vc.io
*/}}
{{- define "imagePullSecretContainersVCIo" }}
{{- $registry := "containers.vc.io" }}
{{- $username := "_" }}
{{- $password := default .Values.agent.key .Values.agent.downloadKey }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" $registry (printf "%s:%s" $username $password | b64enc) | b64enc }}
{{- end }}

{{/*
Output limits or defaults
*/}}
{{- define "vcagent.resources" -}}
{{- $memory := default "512Mi" .memory -}}
{{- $cpu := default 0.5 .cpu -}}
memory: "{{ dict "memory" $memory | include "ensureMemoryMeasurement" }}"
cpu: {{ $cpu }}
{{- end -}}

{{/*
Ensure a unit of memory measurement is added to the value
*/}}
{{- define "ensureMemoryMeasurement" }}
{{- $value := .memory }}
{{- if kindIs "string" $value }}
{{- print $value }}
{{- else }}
{{- print ($value | toString) "Mi" }}
{{- end }}
{{- end }}

{{/*
Composes a container image from a dict containing a "name" field (required), "tag" and "digest" (both optional, if both provided, "digest" has priority)
*/}}
{{- define "image" }}
{{- $name := .name }}
{{- $tag := .tag }}
{{- $digest := .digest }}
{{- if $digest }}
{{- printf "%s@%s" $name $digest }}
{{- else if $tag }}
{{- printf "%s:%s" $name $tag }}
{{- else }}
{{- print $name }}
{{- end }}
{{- end }}

{{- define "volumeMountsForConfigFileInConfigMap" }}
{{- $configMapName := (include "vcagent.fullname" .) }}
{{- $configMapNameSpace := .Release.Namespace }}
{{- $configMap := tpl ( ( "{{ lookup \"v1\" \"ConfigMap\" \"map-namespace\" \"map-name\" | toYaml }}" | replace "map-namespace" $configMapNameSpace ) | replace "map-name" $configMapName ) . }}
{{- if $configMap }}
{{- $configMapObject := $configMap | fromYaml }}
{{- range $key, $val := $configMapObject.data }}
{{- if regexMatch "configuration-disable-kubernetes-sensor\\.yaml" $key }}
{{/* Nothing to do here, this is a special case we want to ignore */}}
{{- else if regexMatch "configuration-opentelemetry\\.yaml" $key }}
{{/* Nothing to do here, this is a special case we want to ignore */}}
{{- else if regexMatch "configuration-prometheus-remote-write\\.yaml" $key }}
{{/* Nothing to do here, this is a special case we want to ignore */}}
{{- else if regexMatch "configuration-.*\\.yaml" $key }}
- name: configuration
  subPath: {{ $key }}
  mountPath: /opt/vc/agent/etc/vc/{{ $key }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}


{{- define "vcagent.commonEnv" -}}
- name: VC_AGENT_LEADER_ELECTOR_PORT
  value: {{ .Values.leaderElector.port | quote }}
- name: VC_ZONE
  value: {{ .Values.zone.name | quote }}
{{- if .Values.cluster.name }}
- name: VC_KUBERNETES_CLUSTER_NAME
  valueFrom:
    configMapKeyRef:
      name: {{ template "vcagent.fullname" . }}
      key: cluster_name
{{- end }}
- name: VC_AGENT_ENDPOINT
  value: {{ .Values.agent.endpointHost | quote }}
- name: VC_AGENT_ENDPOINT_PORT
  value: {{ .Values.agent.endpointPort | quote }}
- name: VC_AGENT_KEY
  valueFrom:
    secretKeyRef:
      name: {{ template "vcagent.keysSecretName" . }}
      key: key
- name: VC_DOWNLOAD_KEY
  valueFrom:
    secretKeyRef:
      name: {{ template "vcagent.keysSecretName" . }}
      key: downloadKey
      optional: true
{{- if .Values.agent.vcMvnRepoUrl }}
- name: VC_MVN_REPOSITORY_URL
  value: {{ .Values.agent.vcMvnRepoUrl | quote }}
{{- end }}
{{- if .Values.agent.proxyHost }}
- name: VC_AGENT_PROXY_HOST
  value: {{ .Values.agent.proxyHost | quote }}
{{- end }}
{{- if .Values.agent.proxyPort }}
- name: VC_AGENT_PROXY_PORT
  value: {{ .Values.agent.proxyPort | quote }}
{{- end }}
{{- if .Values.agent.proxyProtocol }}
- name: VC_AGENT_PROXY_PROTOCOL
  value: {{ .Values.agent.proxyProtocol | quote }}
{{- end }}
{{- if .Values.agent.proxyUser }}
- name: VC_AGENT_PROXY_USER
  value: {{ .Values.agent.proxyUser | quote }}
{{- end }}
{{- if .Values.agent.proxyPassword }}
- name: VC_AGENT_PROXY_PASSWORD
  value: {{ .Values.agent.proxyPassword | quote }}
{{- end }}
{{- if .Values.agent.proxyUseDNS }}
- name: VC_AGENT_PROXY_USE_DNS
  value: {{ .Values.agent.proxyUseDNS | quote }}
{{- end }}
{{- if .Values.agent.listenAddress }}
- name: VC_AGENT_HTTP_LISTEN
  value: {{ .Values.agent.listenAddress | quote }}
{{- end }}
{{- if .Values.agent.redactKubernetesSecrets }}
- name: VC_KUBERNETES_REDACT_SECRETS
  value: {{ .Values.agent.redactKubernetesSecrets | quote }}
{{- end }}
- name: VC_AGENT_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
{{- range $key, $value := .Values.agent.env }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "vcagent.commonVolumeMounts" -}}
{{- if .Values.agent.host.repository }}
- name: repo
  mountPath: /opt/vc/agent/data/repo
{{- end }}
{{- if .Values.agent.additionalBackends -}}
{{- range $index,$backend := .Values.agent.additionalBackends }}
{{- $backendIndex :=add $index 2 }}
- name: additional-backend-{{$backendIndex}}
  subPath: additional-backend-{{$backendIndex}}
  mountPath: /opt/vc/agent/etc/vc/com.vc.agent.main.sender.Backend-{{$backendIndex}}.cfg
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "vcagent.commonVolumes" -}}
- name: configuration
  configMap:
    name: {{ include "vcagent.fullname" . }}
{{- if .Values.agent.host.repository }}
- name: repo
  hostPath:
    path: {{ .Values.agent.host.repository }}
{{- end }}
{{- if .Values.agent.additionalBackends }}
{{- range $index,$backend := .Values.agent.additionalBackends }}
{{ $backendIndex :=add $index 2 -}}
- name: additional-backend-{{$backendIndex}}
  configMap:
    name: {{ include "vcagent.fullname" $ }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "vcagent.livenessProbe" -}}
httpGet:
  host: 127.0.0.1 # localhost because Pod has hostNetwork=true
  path: /status
  port: 42699
initialDelaySeconds: 300 # startupProbe isnt available before K8s 1.16
timeoutSeconds: 3
periodSeconds: 10
failureThreshold: 3
{{- end -}}

{{- define "leader-elector.container" -}}
- name: leader-elector
  image: {{ include "image" .Values.leaderElector.image | quote }}
  env:
    - name: VC_AGENT_POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
  command:
    - "/busybox/sh"
    - "-c"
    - "sleep 12 && /app/server --election=vc --http=localhost:{{ .Values.leaderElector.port }} --id=$(VC_AGENT_POD_NAME)"
  resources:
    requests:
      cpu: 0.1
      memory: "64Mi"
/*  livenessProbe:
    httpGet: # Leader elector /health endpoint expects version 0.5.8 minimum, otherwise always returns 200 OK
      host: 127.0.0.1 # localhost because Pod has hostNetwork=true
      path: /health
      port: {{ .Values.leaderElector.port }}
    initialDelaySeconds: 30
    timeoutSeconds: 3
    periodSeconds: 3
    failureThreshold: 3 */
  ports:
    - containerPort: {{ .Values.leaderElector.port }}
{{- end -}}

{{- define "vcagent.tls-volume" -}}
- name: {{ include "vcagent.fullname" . }}-tls
  secret:
    secretName: {{ .Values.agent.tls.secretName |  default  (printf "%s-tls" (include "vcagent.fullname" .)) }}
    defaultMode: 0440
{{- end -}}

{{- define "vcagent.tls-volumeMounts" -}}
- name: {{ include "vcagent.fullname" . }}-tls
  mountPath: /opt/vc/agent/etc/certs
  readOnly: true
{{- end -}}
