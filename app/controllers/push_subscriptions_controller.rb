# Stores/removes the browser push subscription a device hands us after the user
# opts in. One row per device (keyed by endpoint); re-subscribing upserts rather
# than duplicating. Authenticated-only — a subscription always belongs to a user.
class PushSubscriptionsController < ApplicationController
  # create receives the raw PushSubscription JSON from the browser:
  #   { subscription: { endpoint:, keys: { p256dh:, auth: } } }
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

  # destroy removes this device's subscription on opt-out. Keyed by endpoint
  # (passed in the body) since the browser knows its endpoint, not our row id.
  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end

  # test sends a push to the calling device so the user can confirm delivery.
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
