module RelaxDB

  class ViewCreator
    
    def self.all(*kls)
      klass = kls[0]
      kls_names = kls.map{ |k| %Q("#{k}") }.join(",")
      map = <<-QUERY
      function(doc) {        
        var match = [#{kls_names}].some(function (name) {
          return doc.relaxdb_class && doc.relaxdb_class == name;
        });
        if (match) {
          emit(null, doc);
        }
      }
      QUERY
            
      View.new "#{klass}_all", map, sum_reduce_func      
    end
    
    def self.by_att_list(class_name, *atts)
      key = atts.map { |a| "doc.#{a}" }.join(", ")
      key = atts.size > 1 ? key.sub(/^/, "[").sub(/$/, "]") : key
      prop_check = atts.map { |a| "doc.#{a} !== undefined" }.join(" && ")
    
      map = <<-QUERY
      function(doc) {
        if(doc.relaxdb_class == "#{class_name}" && #{prop_check}) {
          emit(#{key}, doc);
        }
      }
      QUERY
      
      view_name = "#{class_name}_by_" << atts.join("_and_")
      View.new view_name, map, sum_reduce_func
    end
    
  
    def self.has_n(client_class, relationship, target_class, relationship_to_client)
      map = <<-QUERY
        function(doc) {
          if(doc.relaxdb_class == "#{target_class}" && doc.#{relationship_to_client}_id)
            emit(doc.#{relationship_to_client}_id, doc);
        }
      QUERY
      
      view_name = "#{client_class}_#{relationship}"
      View.new view_name, map
    end
  
    def self.references_many(client_class, relationship, target_class, peers)
      map = <<-QUERY
        function(doc) {
          if(doc.relaxdb_class == "#{target_class}" && doc.#{peers}) {
            var i;
            for(i = 0; i < doc.#{peers}.length; i++) {
              emit(doc.#{peers}[i], doc);
            }
          }
        }
      QUERY
      
      view_name = "#{client_class}_#{relationship}"
      View.new view_name, map
    end
    
    def self.sum_reduce_func
      <<-QUERY
      function(keys, values, rereduce) {
        if (rereduce) {
          return sum(values);
        } else {
          return values.length;
        }
      }
      QUERY
    end    
    
  end
  
  class View
    
    attr_reader :view_name
        
    def initialize view_name, map_func, reduce_func = nil
      @view_name = view_name
      @map_func = map_func
      @reduce_func = reduce_func
    end
    
    def design_doc
      @design_doc ||= DesignDocument.get(RelaxDB.dd) 
    end
    
    def save
      dd = design_doc
      dd.add_map_view(@view_name, @map_func)
      dd.add_reduce_view(@view_name, @reduce_func) if @reduce_func
      dd.save
    end
    
    def exists?
      dd = design_doc
      dd.data["views"] && dd.data["views"][@view_name]
    end
    
  end

end
