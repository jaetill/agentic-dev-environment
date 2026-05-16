// Integration test for the lambda-base module.
// Deploys a real Lambda function + API Gateway, verifies key resources, then destroys.
//
// Per ADR-0004 §8 — runs on release tag, not per-PR. Per-test cost target: <$0.10.

package integration

import (
	"context"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	httpclient "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLambdaBaseModule(t *testing.T) {
	t.Parallel()
	requireTestAccount(t)

	prefix := "t-" + random.UniqueId()
	region := awsRegion()
	cfg := awsConfig(t)

	// The test fixture is a tiny Python Lambda that returns 200 on /health
	fixturePath, err := filepath.Abs("../fixtures/hello-lambda.zip")
	require.NoError(t, err, "build the test fixture first: cd ../fixtures && ./build.sh")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Test against a thin wrapper module that consumes lambda-base with test inputs
		TerraformDir: "./fixtures/lambda_base_test",
		Vars: map[string]any{
			"function_name":           prefix + "-fn",
			"env":                     "dev",
			"handler":                 "main.handler",
			"runtime":                 "python3.12",
			"deployment_package_path": fixturePath,
			"release_version":         "test-" + prefix,
		},
		EnvVars: map[string]string{
			"AWS_REGION": region,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify outputs
	functionName := terraform.Output(t, terraformOptions, "function_name")
	assert.Equal(t, prefix+"-fn", functionName)

	logGroupName := terraform.Output(t, terraformOptions, "log_group_name")
	assert.Equal(t, "/aws/lambda/"+prefix+"-fn", logGroupName)

	apiURL := terraform.Output(t, terraformOptions, "api_gateway_url")
	require.NotEmpty(t, apiURL, "API Gateway URL should be created by default")

	// Verify the Lambda exists and has live alias
	lambdaClient := lambda.NewFromConfig(cfg)
	aliasOut, err := lambdaClient.GetAlias(context.Background(), &lambda.GetAliasInput{
		FunctionName: &functionName,
		Name:         awsString("live"),
	})
	require.NoError(t, err)
	assert.Equal(t, "live", *aliasOut.Name)

	// Verify the log group exists with the expected retention
	logsClient := cloudwatchlogs.NewFromConfig(cfg)
	descOut, err := logsClient.DescribeLogGroups(context.Background(), &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: &logGroupName,
	})
	require.NoError(t, err)
	require.Len(t, descOut.LogGroups, 1)
	assert.Equal(t, int32(7), *descOut.LogGroups[0].RetentionInDays, "dev env should have 7-day retention per ADR-0009")

	// Hit the API Gateway /health endpoint with retries (cold-start tolerance)
	healthURL := apiURL + "/health"
	retry.DoWithRetry(t, "wait for API to be healthy", 6, 10*time.Second, func() (string, error) {
		statusCode, _ := httpclient.HttpGet(t, healthURL, nil)
		if statusCode != http.StatusOK {
			return "", &retryError{msg: "got status " + intToStr(statusCode)}
		}
		return "ok", nil
	})
}

// helpers used only in this test
type retryError struct{ msg string }

func (e *retryError) Error() string { return e.msg }
func awsString(s string) *string    { return &s }
func intToStr(i int) string {
	const digits = "0123456789"
	if i < 0 {
		return "-" + intToStr(-i)
	}
	if i == 0 {
		return "0"
	}
	out := ""
	for i > 0 {
		out = string(digits[i%10]) + out
		i /= 10
	}
	return out
}
