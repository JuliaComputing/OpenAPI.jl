# DefaultApi

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**echo_anyof_base_type_post**](DefaultApi.md#echo_anyof_base_type_post) | **POST** /echo_anyof_base_type | 
[**echo_anyof_mapped_pets_post**](DefaultApi.md#echo_anyof_mapped_pets_post) | **POST** /echo_anyof_mapped_pets | 
[**echo_anyof_pets_post**](DefaultApi.md#echo_anyof_pets_post) | **POST** /echo_anyof_pets | 
[**echo_arrays_post**](DefaultApi.md#echo_arrays_post) | **POST** /echo_arrays | 
[**echo_oneof_base_type_post**](DefaultApi.md#echo_oneof_base_type_post) | **POST** /echo_oneof_base_type | 
[**echo_oneof_mapped_pets_post**](DefaultApi.md#echo_oneof_mapped_pets_post) | **POST** /echo_oneof_mapped_pets | 
[**echo_oneof_pets_post**](DefaultApi.md#echo_oneof_pets_post) | **POST** /echo_oneof_pets | 


# **echo_anyof_base_type_post**
> echo_anyof_base_type_post(_api::DefaultApi, any_of_base_type::AnyOfBaseType; _mediaType=nothing) -> AnyOfBaseType, OpenAPI.Clients.ApiResponse <br/>
> echo_anyof_base_type_post(_api::DefaultApi, response_stream::Channel, any_of_base_type::AnyOfBaseType; _mediaType=nothing) -> Channel{ AnyOfBaseType }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**any_of_base_type** | [**AnyOfBaseType**](AnyOfBaseType.md)|  | 

### Return type

[**AnyOfBaseType**](AnyOfBaseType.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_anyof_mapped_pets_post**
> echo_anyof_mapped_pets_post(_api::DefaultApi, any_of_mapped_pets::AnyOfMappedPets; _mediaType=nothing) -> AnyOfMappedPets, OpenAPI.Clients.ApiResponse <br/>
> echo_anyof_mapped_pets_post(_api::DefaultApi, response_stream::Channel, any_of_mapped_pets::AnyOfMappedPets; _mediaType=nothing) -> Channel{ AnyOfMappedPets }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**any_of_mapped_pets** | [**AnyOfMappedPets**](AnyOfMappedPets.md)|  | 

### Return type

[**AnyOfMappedPets**](AnyOfMappedPets.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_anyof_pets_post**
> echo_anyof_pets_post(_api::DefaultApi, any_of_pets::AnyOfPets; _mediaType=nothing) -> AnyOfPets, OpenAPI.Clients.ApiResponse <br/>
> echo_anyof_pets_post(_api::DefaultApi, response_stream::Channel, any_of_pets::AnyOfPets; _mediaType=nothing) -> Channel{ AnyOfPets }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**any_of_pets** | [**AnyOfPets**](AnyOfPets.md)|  | 

### Return type

[**AnyOfPets**](AnyOfPets.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_arrays_post**
> echo_arrays_post(_api::DefaultApi, type_with_all_array_types::TypeWithAllArrayTypes; _mediaType=nothing) -> TypeWithAllArrayTypes, OpenAPI.Clients.ApiResponse <br/>
> echo_arrays_post(_api::DefaultApi, response_stream::Channel, type_with_all_array_types::TypeWithAllArrayTypes; _mediaType=nothing) -> Channel{ TypeWithAllArrayTypes }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**type_with_all_array_types** | [**TypeWithAllArrayTypes**](TypeWithAllArrayTypes.md)|  | 

### Return type

[**TypeWithAllArrayTypes**](TypeWithAllArrayTypes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_oneof_base_type_post**
> echo_oneof_base_type_post(_api::DefaultApi, one_of_base_type::OneOfBaseType; _mediaType=nothing) -> OneOfBaseType, OpenAPI.Clients.ApiResponse <br/>
> echo_oneof_base_type_post(_api::DefaultApi, response_stream::Channel, one_of_base_type::OneOfBaseType; _mediaType=nothing) -> Channel{ OneOfBaseType }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**one_of_base_type** | [**OneOfBaseType**](OneOfBaseType.md)|  | 

### Return type

[**OneOfBaseType**](OneOfBaseType.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_oneof_mapped_pets_post**
> echo_oneof_mapped_pets_post(_api::DefaultApi, one_of_mapped_pets::OneOfMappedPets; _mediaType=nothing) -> OneOfMappedPets, OpenAPI.Clients.ApiResponse <br/>
> echo_oneof_mapped_pets_post(_api::DefaultApi, response_stream::Channel, one_of_mapped_pets::OneOfMappedPets; _mediaType=nothing) -> Channel{ OneOfMappedPets }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**one_of_mapped_pets** | [**OneOfMappedPets**](OneOfMappedPets.md)|  | 

### Return type

[**OneOfMappedPets**](OneOfMappedPets.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **echo_oneof_pets_post**
> echo_oneof_pets_post(_api::DefaultApi, one_of_pets::OneOfPets; _mediaType=nothing) -> OneOfPets, OpenAPI.Clients.ApiResponse <br/>
> echo_oneof_pets_post(_api::DefaultApi, response_stream::Channel, one_of_pets::OneOfPets; _mediaType=nothing) -> Channel{ OneOfPets }, OpenAPI.Clients.ApiResponse



### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**one_of_pets** | [**OneOfPets**](OneOfPets.md)|  | 

### Return type

[**OneOfPets**](OneOfPets.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

