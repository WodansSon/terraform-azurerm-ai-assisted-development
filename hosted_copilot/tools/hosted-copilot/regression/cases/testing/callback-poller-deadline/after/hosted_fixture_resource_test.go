package hostedfixture

import "context"

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
		return client.CreateOrUpdateThenPoll(ctx, id, payload)
	})
}
