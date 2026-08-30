package hostedfixture

import (
	"context"
	"time"
)

type Payload struct{}

type Client struct{}

func (Client) CreateOrUpdateThenPoll(context.Context, string, Payload) error {
	return nil
}

type TestData struct{}

func (TestData) CheckWithClientForResource(callback func(context.Context) error) func() error {
	return func() error {
		return callback(context.Background())
	}
}

func prepareStep(data TestData, client Client, id string, payload Payload) func() error {
	return data.CheckWithClientForResource(func(ctx context.Context) error {
		deadlineCtx, cancel := context.WithTimeout(ctx, 30*time.Minute)
		defer cancel()

		return client.CreateOrUpdateThenPoll(deadlineCtx, id, payload)
	})
}
