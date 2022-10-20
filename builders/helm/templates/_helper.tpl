{{/* Create a fully qualified name */}}
{{- define "looker.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "looker-%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Create chart name and version to be used by labels */}}
{{- define "looker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create the looker service account name stub */}}
{{- define "looker.serviceAccount" -}}
looker-service-account
{{- end }}

{{/* Create common labels */}}
{{- define "looker.labels" -}}
helm.sh/chart: {{ include "looker.chart" . }}
app.kubernetes.io/version: {{ .Values.lookerNodes.version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Create selector labels */}}
{{- define "looker.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Create regular Looker node selector labels */}}
{{- define "looker.nodeSelectorLabels" -}}
{{ include "looker.selectorLabels" . }}
app.kubernetes.io/component: looker-node
{{- end }}

{{/* Create Looker scheduler node selector labels */}}
{{- define "looker.schedulerNodeSelectorLabels" -}}
{{ include "looker.selectorLabels" . }}
app.kubernetes.io/component: scheduler-node
{{- end }}

{{/* Create labels for regular Looker nodes */}}
{{- define "looker.nodeLabels" -}}
{{ include "looker.labels" . }}
{{ include "looker.nodeSelectorLabels" . }}
{{- end }}

{{/* Create labels for Looker scheduler nodes */}}
{{- define "looker.schedulerNodeLabels" -}}
{{ include "looker.labels" . }}
{{ include "looker.schedulerNodeSelectorLabels" . }}
{{- end }}

{{/* Create labels for universal Looker nodes */}}
{{- define "looker.allNodeLabels" -}}
{{ include "looker.labels" . }}
{{ include "looker.selectorLabels" . }}
{{- end }}

{{/* Create appropriate lookerargs flags based on existance of specialized nodes */}}
{{- define "looker.nodeLookerArgs" -}}
{{- if .Values.lookerNodes.dedicatedSchedulerNodes.enabled }}
{{- printf "LOOKERARGS=\"--shared-storage-dir=/mnt/lookerfiles --clustered -H $POD_IP %s --scheduler-threads=0 --unlimited-scheduler-threads=0 --alerts-scheduler-threads=0 --concurrent-render-caching-jobs=0 --concurrent-render-jobs=0\"" .Values.lookerStartupOptions.flags }}
{{- else }}
{{- printf "LOOKERARGS=\"--shared-storage-dir=/mnt/lookerfiles --clustered -H $POD_IP %s\"" .Values.lookerStartupOptions.flags }}
{{- end }}
{{- end }}

{{/* Create appropriate scheduler lookerargs flags */}}
{{- define "looker.schedulerNodeLookerArgs" -}}
{{- $schedulerThreads := printf "--scheduler-threads=%v" .Values.lookerNodes.dedicatedSchedulerNodes.schedulerThreads }}
{{- $unlimitedSchedulerThreads := printf "--unlimited-scheduler-threads=%v" .Values.lookerNodes.dedicatedSchedulerNodes.unlimitedSchedulerThreads }}
{{- $alertsSchedulerThreads := printf "--alerts-scheduler-threads=%v" .Values.lookerNodes.dedicatedSchedulerNodes.alertsSchedulerThreads }}
{{- $concurrentRenderCachingJobs := printf "--concurrent-render-caching-jobs=%v" .Values.lookerNodes.dedicatedSchedulerNodes.concurrentRenderCachingJobs }}
{{- $concurrentRenderJobs := printf "--concurrent-render-jobs=%v" .Values.lookerNodes.dedicatedSchedulerNodes.concurrentRenderJobs }}
{{- printf "LOOKERARGS=\"--shared-storage-dir=/mnt/lookerfiles --clustered -H $POD_IP %s %s %s %s %s\"" $schedulerThreads $unlimitedSchedulerThreads $alertsSchedulerThreads $concurrentRenderCachingJobs $concurrentRenderJobs }}
{{- end }}
