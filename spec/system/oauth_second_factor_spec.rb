# frozen_string_literal: true

require "rotp"

RSpec.describe "Second-factor authentication after OAuth login" do
  include OmniauthHelpers

  fab!(:user)
  fab!(:topic)
  fab!(:totp) { Fabricate(:user_second_factor_totp, user:) }
  fab!(:associated_account) do
    Fabricate(
      :user_associated_account,
      user:,
      provider_name: "google_oauth2",
      provider_uid: OmniauthHelpers::UID,
    )
  end

  let(:login_page) { PageObjects::Pages::Login.new }
  let(:user_menu) { PageObjects::Components::UserMenu.new }

  before do
    enable_auth_provider(:google_oauth2)
    OmniAuth.config.test_mode = true
    mock_google_auth(email: user.email)
    freeze_time
  end

  after { reset_omniauth_config(:google_oauth2) }

  it "signs in the linked user at the original destination only after verifying a code" do
    visit(topic.relative_url)
    login_page.open_from_header
    login_page.click_social_button("google_oauth2")

    expect(page).to have_current_path(%r{\A/session/2fa\?nonce=[a-zA-Z0-9]+\z})
    expect(page).to have_css(".totp-token")
    expect(page).to have_no_css("#login-account-password, #toggle-current-user")

    authenticator = ROTP::TOTP.new(totp.data)
    valid_code = authenticator.now
    nearby_codes = [-30, 0, 30].map { |offset| authenticator.at(Time.now + offset) }
    wrong_code = %w[000000 111111 222222 333333].find { |code| !nearby_codes.include?(code) }
    find(".totp-token .second-factor-token-input").fill_in(with: wrong_code)
    find(".totp-token button[type=submit]").click

    expect(page).to have_css(".alert-error", text: I18n.t("login.invalid_second_factor_code"))
    expect(page).to have_css(".totp-token")
    expect(page).to have_no_css("#toggle-current-user")

    find(".totp-token .second-factor-token-input").fill_in(with: valid_code)
    find(".totp-token button[type=submit]").click

    expect(page).to have_current_path(topic.relative_url)
    expect(page).to have_css("#toggle-current-user")
    user_menu.open.click_profile_tab
    expect(page).to have_css("#quick-access-profile .summary a[href='/u/#{user.username}/summary']")
  end
end
