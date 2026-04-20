{{- define "grantclaw.fullname" -}}
grantclaw-{{ .Values.bot.name }}
{{- end -}}

{{- define "grantclaw.labels" -}}
app.kubernetes.io/name: grantclaw
app.kubernetes.io/instance: {{ .Values.bot.name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}
