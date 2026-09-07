#include "../incs/CgiHandler.hpp"
#include "../incs/CgiEnv.hpp"
#include "../incs/Logger.hpp"
#include <fstream>
#include <sstream>

// argv for execve
static std::vector<std::string> buildCgiArgs(const HTTPRequest& request) {

	std::vector<std::string> args;
	args.push_back(request.cgi.binary_path);
	args.push_back(request.resolved.filepath);
	return args;

}

// read the body back off disk, that's our cgi stdin
static std::string readCgiInput(const HTTPRequest& request) {

	// small bodies live in memory, only big ones spool to disk
	if (request.body.sink == HEAP)
		return request.body.temp;

	if (request.body.path.empty())
		return "";

	std::ifstream file(request.body.path.c_str(), std::ios::binary);
	if (!file.is_open())
		return "";

	std::ostringstream ss;
	ss << file.rdbuf();
	return ss.str();

}

StatusCode handleCGI(HTTPRequest& request, HTTPResponse& response,
					 const Config::Socket& socket) {

	(void)response; // filled in later, by CgiProcess::buildResponse()

	std::string cgi_input = readCgiInput(request);
	std::vector<std::string> cgi_args = buildCgiArgs(request);
	std::string working_dir = request.resolved.filepath.substr(0, request.resolved.filepath.find_last_of('/'));

	std::map<std::string, std::string> env = build_cgi_env(request, socket,
															*request.resolved.domain,
															*request.resolved.location,
															request.resolved.filepath);

	request.cgi_process = new CgiProcess(request.cgi.binary_path, cgi_args, env, cgi_input, working_dir);

	if (!request.cgi_process->valid()) {
		log.error("cgi: failed to open pipes for " + request.cgi.binary_path);
		return INTERNAL_SERVER_ERROR;
	}

	if (!request.cgi_process->spawn()) {
		log.error("cgi: failed to spawn " + request.cgi.binary_path);
		return INTERNAL_SERVER_ERROR;
	}

	// epoll registration is still ahead, server side
	return NO_STATUS;

}
