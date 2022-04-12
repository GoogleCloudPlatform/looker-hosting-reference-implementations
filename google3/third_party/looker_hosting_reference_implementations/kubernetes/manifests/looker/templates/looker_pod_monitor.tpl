apiVersion: monitoring.gke.io/v1alpha1
kind: PodMonitor
metadata:
  name: looker-monitor
spec:
  selector:
    matchLabels:
      app: looker-clustered-${env_label}
  podMetricsEndpoints:
    - port: jmx-metrics
