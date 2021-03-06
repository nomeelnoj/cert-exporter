package exporters

import (
	"github.com/joe-elliott/cert-exporter/src/metrics"
)

// CertExporter exports PEM file certs
type SecretExporter struct {
}

// ExportMetrics exports the provided PEM file
func (c *SecretExporter) ExportMetrics(bytes []byte, keyName string, secretName string, secretNamespace string) error {

	metric, err := secondsToExpiryFromCertAsBytes(bytes)

	if err != nil {
		return err
	}

	metrics.SecretExpirySeconds.WithLabelValues(keyName, secretName, secretNamespace).Set(metric.durationUntilExpiry)
	metrics.SecretNotAfterTimestamp.WithLabelValues(keyName, secretName, secretNamespace).Set(metric.notAfter)
	return nil
}
