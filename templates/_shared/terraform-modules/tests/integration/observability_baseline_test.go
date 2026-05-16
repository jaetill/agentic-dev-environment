// Integration test for the observability-baseline module.
// Deploys budget + X-Ray sampling rule + log groups; verifies; destroys.
//
// Per ADR-0004 §8 — runs on release tag, not per-PR.

package integration

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestObservabilityBaselineModule(t *testing.T) {
	t.Parallel()
	requireTestAccount(t)

	prefix := "t-" + random.UniqueId()
	cfg := awsConfig(t)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/observability_baseline_test",
		Vars: map[string]any{
			"project_name": prefix,
			"env":          "dev",
			// Skip Grafana resources in this test to avoid needing Grafana auth
			"grafana_enabled": false,
			"additional_log_group_names": []string{
				"/" + prefix + "/app",
			},
		},
		EnvVars: map[string]string{
			"AWS_REGION": awsRegion(),
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify outputs
	retention := terraform.OutputRequired(t, terraformOptions, "log_retention_days")
	assert.Equal(t, "7", retention, "dev env should default to 7-day retention")

	samplingRate := terraform.OutputRequired(t, terraformOptions, "xray_sampling_rate")
	assert.Equal(t, "1", samplingRate, "dev env should default to 100% X-Ray sampling")

	budget := terraform.OutputRequired(t, terraformOptions, "budget_amount_usd")
	assert.Equal(t, "25", budget, "dev env should default to $25/mo budget")

	// Verify the additional log group exists with correct retention
	logsClient := cloudwatchlogs.NewFromConfig(cfg)
	logGroupName := "/" + prefix + "/app"
	descOut, err := logsClient.DescribeLogGroups(context.Background(), &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: &logGroupName,
	})
	require.NoError(t, err)
	require.Len(t, descOut.LogGroups, 1)
	assert.Equal(t, int32(7), *descOut.LogGroups[0].RetentionInDays)
}
