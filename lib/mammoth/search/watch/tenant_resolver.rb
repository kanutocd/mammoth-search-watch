# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class TenantResolver
        attr_reader :configuration

        def initialize(configuration)
          @configuration = configuration
        end

        def call(request, payload)
          return configuration.global_tenant_id unless blank?(configuration.global_tenant_id)

          payload_tenant_id(payload) ||
            header_tenant_id(request) ||
            raise(ConfigurationError, "tenant_id is required")
        end

        private

        def payload_tenant_id(payload)
          payload["tenant_id"] unless blank?(payload["tenant_id"])
        end

        def header_tenant_id(request)
          headers = request.respond_to?(:headers) ? request.headers : {}
          value = headers[configuration.tenancy.tenant_header] || headers[configuration.tenancy.tenant_header.upcase.tr("-", "_")]
          blank?(value) ? nil : value
        end

        def blank?(value)
          value.nil? || value == ""
        end
      end
    end
  end
end
