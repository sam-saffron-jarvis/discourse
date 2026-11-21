# frozen_string_literal: true

module SecondFactor::Actions
  class OmniauthLogin < Base
    def no_second_factors_enabled!(params)
      # The controller handles login when there is no challenge.
    end

    def second_factor_auth_required!(params)
      {
        callback_path: omniauth_second_factor_path,
        callback_method: "POST",
        callback_params: @opts,
      }
    end

    def second_factor_auth_completed!(callback_params)
      callback_params
    end
  end
end
