class PushSubscriptionsController < ApplicationController
  def create
    endpoint = params.dig(:subscription, :endpoint)
    keys = params.dig(:subscription, :keys) || {}

    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    subscription.assign_attributes(
      p256dh_key: keys[:p256dh],
      auth_key: keys[:auth],
      user_agent: request.user_agent
    )

    if subscription.save
      head :created
    else
      head :unprocessable_entity
    end
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end

  def test
    subscription = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])
    return head :not_found unless subscription

    if subscription.deliver(title: t("push.test.title"), body: t("push.test.body"), path: notifications_path)
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
