package main

import (
	"context"
	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	lambda.Start(func(ctx context.Context) (string, error) {
		return Ping()
	})
}

func Ping() (string, error) {
	return "Ok", nil
}
