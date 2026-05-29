# frozen_string_literal: true

module ConsoleKit
  # Blocks ActiveRecord write operations when activated.
  # Call install! once at startup (idempotent). Call activate! per session.
  # Rails 7.1+ defense-in-depth: also sets connection.prevent_writes for raw SQL protection.
  module ReadonlyMode
    INSTANCE_WRITE_METHODS = %i[save save! update_columns update_column destroy destroy! delete].freeze
    CLASS_WRITE_METHODS    = %i[
      create create! insert insert! insert_all insert_all!
      update_all delete_all destroy_all upsert upsert_all
    ].freeze

    @active    = false
    @installed = false

    class << self
      def activate!
        @active = true
        apply_prevent_writes!(true)
      end

      def deactivate!
        @active = false
        apply_prevent_writes!(false)
      end

      def active? = @active

      def install!
        return if @installed
        return unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.prepend(InstanceMethods)
        ActiveRecord::Base.singleton_class.prepend(ClassMethods)
        @installed = true
      end

      private

      def apply_prevent_writes!(value)
        return unless defined?(ActiveRecord::Base)

        conn = ActiveRecord::Base.connection
        conn.prevent_writes = value if conn.respond_to?(:prevent_writes=)
      rescue StandardError
        nil
      end
    end

    # Intercepts AR instance write methods to raise ReadonlyViolation when readonly mode is active.
    module InstanceMethods
      INSTANCE_WRITE_METHODS.each do |m|
        define_method(m) do |*args, **kwargs, &block|
          raise ReadonlyViolation, "#{m} blocked: readonly mode active" if ReadonlyMode.active?

          super(*args, **kwargs, &block)
        end
      end
    end

    # Intercepts AR class-level write methods to raise ReadonlyViolation when readonly mode is active.
    module ClassMethods
      CLASS_WRITE_METHODS.each do |m|
        define_method(m) do |*args, **kwargs, &block|
          raise ReadonlyViolation, "#{m} blocked: readonly mode active" if ReadonlyMode.active?

          super(*args, **kwargs, &block)
        end
      end
    end
  end
end
