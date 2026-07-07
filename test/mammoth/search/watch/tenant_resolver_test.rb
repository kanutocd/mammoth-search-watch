# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class TenantResolverTest < Minitest::Test
        Request = Struct.new(:headers)

        def test_global_tenant_overrides_request_values
          configuration = Configuration.new(
            { "tenancy" => { "default_tenant_id" => "tenant_global" } },
            env: {}
          )
          resolver = TenantResolver.new(configuration)

          tenant_id = resolver.call(Request.new({ "x-mammoth-tenant-id" => "tenant_request" }),
                                    { "tenant_id" => "tenant_payload" })

          assert_equal "tenant_global", tenant_id
        end

        def test_payload_tenant_is_used_when_no_global_tenant_exists
          configuration = Configuration.new({}, env: {})
          resolver = TenantResolver.new(configuration)

          tenant_id = resolver.call(Request.new({}), { "tenant_id" => "tenant_payload" })

          assert_equal "tenant_payload", tenant_id
        end

        def test_exact_header_tenant_is_used_when_payload_is_blank
          configuration = Configuration.new({}, env: {})
          resolver = TenantResolver.new(configuration)

          tenant_id = resolver.call(Request.new({ "x-mammoth-tenant-id" => "tenant_header" }), { "tenant_id" => "" })

          assert_equal "tenant_header", tenant_id
        end

        def test_header_tenant_is_used_when_payload_is_blank
          configuration = Configuration.new({}, env: {})
          resolver = TenantResolver.new(configuration)

          tenant_id = resolver.call(Request.new({ "X_MAMMOTH_TENANT_ID" => "tenant_header" }), { "tenant_id" => "" })

          assert_equal "tenant_header", tenant_id
        end

        def test_missing_tenant_raises_configuration_error
          configuration = Configuration.new({}, env: {})
          resolver = TenantResolver.new(configuration)

          assert_raises(ConfigurationError) do
            resolver.call(Request.new({}), {})
          end
        end
      end
    end
  end
end
