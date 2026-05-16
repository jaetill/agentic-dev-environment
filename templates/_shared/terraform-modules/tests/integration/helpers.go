// Package integration contains Terratest integration tests for the platform's
// shared Terraform modules. Per ADR-0004 §8 and Terratest 2026 best practices.
package integration

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"os"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/stretchr/testify/require"
)

// uniquePrefix returns a short random suffix for resource isolation across
// parallel test runs. Per Terratest best practice: each test gets unique names
// so concurrent runs don't collide.
func uniquePrefix(t *testing.T, base string) string {
	t.Helper()
	b := make([]byte, 4)
	_, err := rand.Read(b)
	require.NoError(t, err)
	return base + "-" + hex.EncodeToString(b)
}

// awsRegion returns the AWS region from env or defaults to us-east-1.
func awsRegion() string {
	if r := os.Getenv("AWS_REGION"); r != "" {
		return r
	}
	return "us-east-1"
}

// awsConfig loads the default AWS SDK config for the test region.
func awsConfig(t *testing.T) aws.Config {
	t.Helper()
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion(awsRegion()),
	)
	require.NoError(t, err, "failed to load AWS config; ensure AWS credentials are configured")
	return cfg
}

// requireTestAccount asserts that we're running against a dedicated test
// account, not dev/staging/prod. Per ADR-0006: never run integration tests
// against environments with real data.
func requireTestAccount(t *testing.T) {
	t.Helper()
	if os.Getenv("AWS_TEST_ACCOUNT_CONFIRMED") != "true" {
		t.Skip("Set AWS_TEST_ACCOUNT_CONFIRMED=true to confirm you're running against a dedicated test account")
	}
}
