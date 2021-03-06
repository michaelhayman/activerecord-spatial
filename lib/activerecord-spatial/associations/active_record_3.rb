
module ActiveRecord
  module Associations
    class Builder::Spatial < Builder::HasMany #:nodoc:
      self.macro = SPATIAL_MACRO
      self.valid_options += VALID_SPATIAL_OPTIONS
      self.valid_options -= INVALID_SPATIAL_OPTIONS
    end

    class Preloader #:nodoc:
      class SpatialAssociation < HasMany #:nodoc:
        def records_for(ids)
          table_name = reflection.quoted_table_name
          join_name = model.quoted_table_name
          column = %{#{SPATIAL_JOIN_QUOTED_NAME}.#{model.quoted_primary_key}}
          geom = {
            :class => model,
            :table_alias => SPATIAL_JOIN_NAME
          }

          if reflection.options[:geom].is_a?(Hash)
            geom.merge!(reflection.options[:geom])
          else
            geom[:column] = reflection.options[:geom]
          end

          scoped.
            select(%{array_to_string(array_agg(#{column}), ',') AS "#{SPATIAL_FIELD_ALIAS}"}).
            joins(
              "INNER JOIN #{join_name} AS #{SPATIAL_JOIN_QUOTED_NAME} ON (" <<
                klass.send("st_#{reflection.options[:relationship]}",
                  geom,
                  (reflection.options[:scope_options] || {}).merge(
                    :column => reflection.options[:foreign_geom]
                  )
                ).where_values.join(' AND ') <<
              ")"
            ).
            where(model.arel_table.alias(SPATIAL_JOIN_NAME)[model.primary_key].in(ids)).
            group(table[klass.primary_key])
        end
      end
    end

    class AssociationScope #:nodoc:
      def add_constraints_with_spatial(scope)
        return add_constraints_without_spatial(scope) if !self.association.is_a?(SpatialAssociation)

        tables = construct_tables

        chain.each_with_index do |reflection, i|
          table, foreign_table = tables.shift, tables.first

          conditions = self.conditions[i]
          geom_options = {
            :class => self.association.klass
          }

          if self.association.geom.is_a?(Hash)
            geom_options.merge!(
              :value => owner[self.association.geom[:name]]
            )
            geom_options.merge!(self.association.geom)
          else
            geom_options.merge!(
              :value => owner[self.association.geom],
              :name => self.association.geom
            )
          end

          if reflection == chain.last
            scope = scope.send("st_#{self.association.relationship}", geom_options, self.association.scope_options)

            if reflection.type
              scope = scope.where(table[reflection.type].eq(owner.class.base_class.name))
            end

            conditions.each do |condition|
              scope = scope.where(interpolate(condition))
            end
          else
            constraint = scope.where(
              scope.send(
                "st_#{self.association.relationship}",
                owner[self.association.foreign_geom],
                self.association.scope_options
              ).where_values
            ).join(' AND ')

            if reflection.type
              type = chain[i + 1].klass.base_class.name
              constraint = table[reflection.type].eq(type).and(constraint)
            end

            scope = scope.joins(join(foreign_table, constraint))

            unless conditions.empty?
              scope = scope.where(sanitize(conditions, table))
            end
          end
        end

        scope
      end
      alias_method_chain :add_constraints, :spatial
    end
  end
end

module ActiveRecordSpatial::Associations
  module ClassMethods #:nodoc:
    def has_many_spatially(name, options = {}, &extension)
      options = build_options(options)

      if !ActiveRecordSpatial::SpatialScopeConstants::RELATIONSHIPS.include?(options[:relationship].to_s)
        raise ArgumentError.new(%{Invalid spatial relationship "#{options[:relationship]}", expected one of #{ActiveRecordSpatial::SpatialScopeConstants::RELATIONSHIPS.inspect}})
      end

      ActiveRecord::Associations::Builder::Spatial.build(self, name, options, &extension)
    end
  end
end

