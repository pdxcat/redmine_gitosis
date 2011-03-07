class GitosisObserver < ActiveRecord::Observer
  observe :project, :user, :gitosis_public_key, :member, :role, :repository
  
  def after_save(object) ; update_repositories(object) ; end
  def after_destroy(object) ; update_repositories(object) ; end
  
  protected
  
  def update_repositories(object)
    case object
      when Project: Gitosis::update_repositories(object)
      when Repository: Gitosis::update_repositories(object.project)
      when User: Gitosis::update_repositories(object.projects)
      when GitosisPublicKey: Gitosis::update_repositories(object.user.projects)
      when Member: Gitosis::update_repositories(object.project)
      when Role: Gitosis::update_repositories(object.members.map(&:project).uniq.compact)
    end
  end
  
end
